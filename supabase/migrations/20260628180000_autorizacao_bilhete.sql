-- ============================================================================
-- Bilhete de autorização (Opção C — fila sem PIN), Sprint 3a
-- ----------------------------------------------------------------------------
-- O PIN é validado UMA vez, a sério, na iniciar_picagem (online, antes da
-- câmara). Em vez de guardar o PIN na fila para o revalidar no drain, a
-- iniciar_picagem emite um BILHETE (linha em `autorizacao`): prova de que
-- aquele trabalhador foi autenticado naquela loja. A fila leva o bilhete, não
-- o PIN. O drain consome o bilhete (uso único).
--
-- Infalsificável: só a iniciar_picagem (SECURITY DEFINER) escreve em
-- `autorizacao`; um kiosk adulterado não consegue inserir um bilhete válido.
--
-- FRONTEIRA: isto cobre o 3a (autorização online). O 3b (autorização offline
-- durante corte prolongado) precisará de uma prova local diferente — decisão
-- separada. Esta migração NÃO trata o 3b.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Tabela do bilhete
-- ----------------------------------------------------------------------------
create table if not exists public.autorizacao (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresa(id),
  trabalhador_id uuid not null,
  loja_id        uuid not null,
  criada_em      timestamptz not null default now(),
  expira_em      timestamptz not null,
  usada_em       timestamptz,
  created_at     timestamptz not null default now(),
  foreign key (empresa_id, trabalhador_id) references public.trabalhador (empresa_id, id),
  foreign key (empresa_id, loja_id)        references public.loja (empresa_id, id)
);

alter table public.autorizacao enable row level security;

-- O kiosk NUNCA toca nesta tabela diretamente (só via as RPCs SECURITY DEFINER).
-- O admin pode ler/auditar (emitidos vs usados).
drop policy if exists admin_empresa on public.autorizacao;
create policy admin_empresa on public.autorizacao
  for all
  using      (public.is_admin() and empresa_id = public.empresa_atual())
  with check (public.is_admin() and empresa_id = public.empresa_atual());

grant select, insert, update, delete on public.autorizacao to authenticated;

-- ----------------------------------------------------------------------------
-- 2. iniciar_picagem — valida PIN (igual) e EMITE o bilhete.
-- ----------------------------------------------------------------------------
create or replace function public.iniciar_picagem(
  p_codigo_pessoal text,
  p_pin            text
)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    record;
  v_ultima  record;
  v_aut     uuid := gen_random_uuid();
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode iniciar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;

  select t.id, t.nome
    into v_trab
    from public.trabalhador t
   where t.empresa_id     = v_empresa
     and t.codigo_pessoal = p_codigo_pessoal
     and t.ativo          = true
     and t.pin is not null
     and t.pin            = p_pin;

  if v_trab.id is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  -- bilhete de uso único: prova de que o PIN foi validado agora
  insert into public.autorizacao (id, empresa_id, trabalhador_id, loja_id, expira_em)
  values (v_aut, v_empresa, v_trab.id, v_loja, now() + interval '6 hours');

  select p.tipo, v.momento_dispositivo
    into v_ultima
    from public.picagem p
    join public.verificacao v
      on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
   where p.empresa_id     = v_empresa
     and v.trabalhador_id = v_trab.id
     and v.momento_dispositivo >=
         (date_trunc('day', (now() at time zone 'Europe/Lisbon')) at time zone 'Europe/Lisbon')
   order by v.momento_dispositivo desc
   limit 1;

  return json_build_object(
    'autorizacao_id', v_aut,
    'trabalhador_id', v_trab.id,
    'nome',           v_trab.nome,
    'ultima_tipo',    v_ultima.tipo,
    'ultima_momento', v_ultima.momento_dispositivo
  );
end
$function$;

revoke all on function public.iniciar_picagem(text, text) from public;
grant execute on function public.iniciar_picagem(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. registar_picagem — assinatura NOVA: consome o bilhete, SEM PIN.
--    (autorizacao_id, tipo, momento, chave_idempotencia)
-- ----------------------------------------------------------------------------
drop function if exists public.registar_picagem(text, text, text, timestamptz, uuid);

create or replace function public.registar_picagem(
  p_autorizacao_id      uuid,
  p_tipo                text,
  p_momento_dispositivo timestamptz,
  p_chave_idempotencia  uuid
)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    uuid;
  v_id      uuid := gen_random_uuid();
  v_path    text;
  v_exist_id   uuid;
  v_exist_path text;
  v_aut     record;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento_dispositivo is null then
    raise exception 'momento do dispositivo em falta';
  end if;
  if p_chave_idempotencia is null then
    raise exception 'chave de idempotência em falta';
  end if;
  if p_autorizacao_id is null then
    raise exception 'autorização em falta';
  end if;

  -- idempotência primeiro (retomada da fila com a mesma chave)
  select id, foto_url into v_exist_id, v_exist_path
    from public.verificacao
   where empresa_id = v_empresa
     and chave_idempotencia = p_chave_idempotencia;

  if v_exist_id is not null then
    return json_build_object(
      'verificacao_id', v_exist_id, 'foto_path', v_exist_path, 'repetida', true);
  end if;

  -- consumir o bilhete: existe, desta empresa/loja, não usado, não expirado
  select * into v_aut
    from public.autorizacao
   where id = p_autorizacao_id
     and empresa_id = v_empresa
     and loja_id    = v_loja
   for update;

  if v_aut.id is null then
    raise exception 'autorização inválida'
      using errcode = 'invalid_authorization_specification';
  end if;
  if v_aut.usada_em is not null then
    raise exception 'autorização já utilizada'
      using errcode = 'invalid_authorization_specification';
  end if;
  if v_aut.expira_em < now() then
    raise exception 'autorização expirada'
      using errcode = 'invalid_authorization_specification';
  end if;

  v_trab := v_aut.trabalhador_id;

  -- caminho: {empresa}/{loja}/{trabalhador}/{verificacao_id}.jpg
  v_path := v_empresa::text || '/' || v_loja::text || '/'
            || v_trab::text || '/' || v_id::text || '.jpg';

  update public.autorizacao set usada_em = now() where id = p_autorizacao_id;

  begin
    insert into public.verificacao
      (id, empresa_id, trabalhador_id, loja_id,
       momento_dispositivo, momento_servidor, foto_url, chave_idempotencia)
    values
      (v_id, v_empresa, v_trab, v_loja,
       p_momento_dispositivo, now(), v_path, p_chave_idempotencia);

    insert into public.picagem (empresa_id, verificacao_id, tipo)
    values (v_empresa, v_id, p_tipo);

  exception when unique_violation then
    select id, foto_url into v_exist_id, v_exist_path
      from public.verificacao
     where empresa_id = v_empresa
       and chave_idempotencia = p_chave_idempotencia;
    return json_build_object(
      'verificacao_id', v_exist_id, 'foto_path', v_exist_path, 'repetida', true);
  end;

  return json_build_object(
    'verificacao_id', v_id, 'foto_path', v_path, 'repetida', false);
end
$function$;

revoke all on function public.registar_picagem(uuid, text, timestamptz, uuid) from public;
grant execute on function public.registar_picagem(uuid, text, timestamptz, uuid) to authenticated;

commit;
