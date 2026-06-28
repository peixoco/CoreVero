-- ============================================================================
-- Imutabilidade do registo de tempos + correções sancionadas (Frente A)
-- ----------------------------------------------------------------------------
-- Imutável NÃO é "ninguém mexe" — é "ninguém mexe em silêncio". A lei (CT
-- art. 202.º) obriga o empregador a corrigir registos; o que proíbe é a hora
-- ser reescrita sem rasto. Logo:
--
--   - APAGAR picagem/verificação            -> BLOQUEADO (nunca se apaga prova)
--   - EDITAR tipo/hora/trabalhador          -> BLOQUEADO (reescrita silenciosa)
--   - foto_url -> null (job de retenção)    -> permitido
--   - anular* (marcar anulada, com autor)   -> permitido (via RPC auditada)
--
-- Correções (append-only, auditadas):
--   - corrigir_picagem  : ADICIONA a picagem em falta (esqueceu entrada/saída)
--   - anular_picagem    : MARCA anulada (não apaga); o cálculo de horas ignora-a
--   Corrigir uma hora errada = anular a errada + adicionar a certa.
--
-- Toda a correção fica com correcao_manual=true + criada_por / anulada_por.
-- ============================================================================

begin;

-- 1) Anulação na picagem (soft-void, auditado).
alter table public.picagem
  add column if not exists anulada         boolean not null default false,
  add column if not exists anulada_por     uuid,
  add column if not exists anulada_em       timestamptz,
  add column if not exists motivo_anulacao text;

-- 2) Trigger de imutabilidade — verificacao (foto_url livre p/ retenção).
create or replace function public.bloquear_edicao_verificacao() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'registo de tempos imutável: verificação não pode ser apagada';
  end if;
  if NEW.id is distinct from OLD.id
     or NEW.empresa_id is distinct from OLD.empresa_id
     or NEW.trabalhador_id is distinct from OLD.trabalhador_id
     or NEW.loja_id is distinct from OLD.loja_id
     or NEW.momento_dispositivo is distinct from OLD.momento_dispositivo
     or NEW.momento_servidor is distinct from OLD.momento_servidor
     or NEW.chave_idempotencia is distinct from OLD.chave_idempotencia
     or NEW.autorizacao_offline is distinct from OLD.autorizacao_offline
     or NEW.correcao_manual is distinct from OLD.correcao_manual
     or NEW.criada_por is distinct from OLD.criada_por then
    raise exception 'registo de tempos imutável: só foto_url pode mudar (retenção)';
  end if;
  return NEW;
end
$function$;
drop trigger if exists trg_imutavel_verificacao on public.verificacao;
create trigger trg_imutavel_verificacao
  before update or delete on public.verificacao
  for each row execute function public.bloquear_edicao_verificacao();

-- 3) Trigger de imutabilidade — picagem (anulada* livre).
create or replace function public.bloquear_edicao_picagem() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'registo de tempos imutável: picagem não pode ser apagada';
  end if;
  if NEW.id is distinct from OLD.id
     or NEW.empresa_id is distinct from OLD.empresa_id
     or NEW.verificacao_id is distinct from OLD.verificacao_id
     or NEW.tipo is distinct from OLD.tipo then
    raise exception 'registo de tempos imutável: tipo/hora não editáveis — anule e crie nova';
  end if;
  return NEW;
end
$function$;
drop trigger if exists trg_imutavel_picagem on public.picagem;
create trigger trg_imutavel_picagem
  before update or delete on public.picagem
  for each row execute function public.bloquear_edicao_picagem();

-- 4) Defesa extra: o cliente não atualiza/apaga estes registos diretamente.
--    (As correções passam só pelas RPCs SECURITY DEFINER abaixo.)
revoke update, delete on public.picagem    from authenticated, anon;
revoke update, delete on public.verificacao from authenticated, anon;

-- 5) corrigir_picagem — adiciona a picagem em falta.
create or replace function public.corrigir_picagem(
  p_trabalhador_id uuid, p_tipo text, p_momento timestamptz,
  p_motivo text default null, p_loja_id uuid default null)
returns json language plpgsql security definer set search_path to '' as $function$
declare
  v_emp uuid := public.empresa_atual();
  v_loja uuid; v_n int;
  v_vid uuid := gen_random_uuid(); v_pid uuid;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode='insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento is null then raise exception 'momento em falta'; end if;
  if not exists (select 1 from public.trabalhador where id=p_trabalhador_id and empresa_id=v_emp) then
    raise exception 'trabalhador não encontrado nesta empresa';
  end if;

  -- Resolver a loja: param -> última picagem do trabalhador -> única loja ativa.
  v_loja := p_loja_id;
  if v_loja is not null and not exists (select 1 from public.loja where id=v_loja and empresa_id=v_emp) then
    raise exception 'loja não pertence à empresa';
  end if;
  if v_loja is null then
    select v.loja_id into v_loja
      from public.picagem p
      join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
     where v.empresa_id=v_emp and v.trabalhador_id=p_trabalhador_id
     order by v.momento_dispositivo desc limit 1;
  end if;
  if v_loja is null then
    select count(*), min(id) into v_n, v_loja from public.loja where empresa_id=v_emp and ativa=true;
    if v_n <> 1 then v_loja := null; end if;
  end if;
  if v_loja is null then raise exception 'indique a loja da correção'; end if;

  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, momento_servidor,
     foto_url, chave_idempotencia, autorizacao_offline, correcao_manual, criada_por)
  values
    (v_vid, v_emp, p_trabalhador_id, v_loja, p_momento, now(),
     null, gen_random_uuid(), false, true, auth.uid());

  insert into public.picagem (empresa_id, verificacao_id, tipo)
  values (v_emp, v_vid, p_tipo) returning id into v_pid;

  return json_build_object('picagem_id', v_pid, 'verificacao_id', v_vid, 'loja_id', v_loja);
end
$function$;

-- 6) anular_picagem — marca anulada (não apaga).
create or replace function public.anular_picagem(p_picagem_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode='insufficient_privilege';
  end if;
  update public.picagem
     set anulada=true, anulada_por=auth.uid(), anulada_em=now(), motivo_anulacao=p_motivo
   where id=p_picagem_id and empresa_id=public.empresa_atual() and anulada=false;
  if not found then raise exception 'picagem não encontrada ou já anulada'; end if;
end
$function$;

revoke all on function public.corrigir_picagem(uuid,text,timestamptz,text,uuid) from public;
revoke all on function public.anular_picagem(uuid,text) from public;
grant execute on function public.corrigir_picagem(uuid,text,timestamptz,text,uuid) to authenticated;
grant execute on function public.anular_picagem(uuid,text) to authenticated;

-- 7) Cálculo de horas exclui anuladas (mesmas colunas + filtro).
create or replace view public.vista_horas_dia with (security_invoker=true) as
with eventos as (
  select v.empresa_id, v.trabalhador_id, v.momento_dispositivo as momento, p.tipo,
    count(*) filter (where p.tipo='entrada') over (partition by v.empresa_id, v.trabalhador_id
      order by v.momento_dispositivo rows between unbounded preceding and current row) as turno_no
  from public.picagem p
  join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
  where not p.anulada
),
segmentos as (
  select empresa_id, trabalhador_id, turno_no, momento, tipo,
    lead(momento) over (partition by empresa_id, trabalhador_id, turno_no order by momento) as fim,
    case when tipo in ('entrada','fim_intervalo') then 'trabalho'
         when tipo='inicio_intervalo' then 'pausa' else 'fora' end as estado
  from eventos
),
turnos as (
  select empresa_id, trabalhador_id, turno_no,
    date_trunc('day',(min(momento) at time zone 'Europe/Lisbon'))::date as dia,
    coalesce(sum(case when estado='trabalho' and fim is not null then extract(epoch from (fim-momento)) end),0) as seg_trab,
    coalesce(sum(case when estado='pausa' and fim is not null then extract(epoch from (fim-momento)) end),0) as seg_pausa,
    bool_or(tipo='saida') as fechado,
    bool_or(estado in ('trabalho','pausa') and fim is null) as tem_aberto
  from segmentos group by empresa_id, trabalhador_id, turno_no
)
select empresa_id, trabalhador_id, dia,
  round((sum(seg_trab)/3600.0)::numeric,2)  as horas_trabalho,
  round((sum(seg_pausa)/3600.0)::numeric,2) as horas_pausa,
  sum(seg_trab)::int  as seg_trabalho,
  sum(seg_pausa)::int as seg_pausa,
  count(*)            as turnos,
  bool_and(fechado)   as todos_fechados,
  bool_or(not fechado or tem_aberto) as incompleto
from turnos group by empresa_id, trabalhador_id, dia;

-- 8) Listagem de picagens expõe anulada + correção manual (badges no admin).
create or replace view public.vista_picagem with (security_invoker=true) as
  select p.id as picagem_id, p.empresa_id, p.tipo,
    v.id as verificacao_id, v.momento_dispositivo, v.momento_servidor, v.foto_url,
    v.loja_id, l.nome as loja_nome, v.trabalhador_id, t.nome as trabalhador_nome, t.codigo_pessoal,
    p.anulada, p.motivo_anulacao, v.correcao_manual
  from public.picagem p
  join public.verificacao v on v.empresa_id=p.empresa_id and v.id=p.verificacao_id
  join public.loja l on l.empresa_id=v.empresa_id and l.id=v.loja_id
  join public.trabalhador t on t.empresa_id=v.empresa_id and t.id=v.trabalhador_id;

commit;
