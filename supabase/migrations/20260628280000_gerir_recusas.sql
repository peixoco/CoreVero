-- ============================================================================
-- Gestão de picagens recusadas + primitivo de correção manual (Frente A, início)
-- ----------------------------------------------------------------------------
-- Uma recusa é uma tentativa de picagem offline rejeitada no drain (cache
-- obsoleta). O gestor tem de poder resolvê-la:
--   - ACEITAR  -> cria uma picagem real (correção manual, hora original, sem
--                 foto), atribuída ao admin. Para ausências que foram reais.
--   - DESCARTAR -> marca resolvida sem criar nada. Para tentativas ilegítimas.
--
-- Isto introduz o primitivo de CORREÇÃO MANUAL da Frente A: o registo legal
-- corrige-se por NOVO registo autenticado (append-only), nunca por edição.
-- A verificacao ganha `correcao_manual` + `criada_por` para auditoria — uma
-- inspeção (ACT) distingue registos capturados no dispositivo de correções do
-- empregador.
-- ============================================================================

begin;

-- 1) Estado de resolução na recusa.
alter table public.picagem_recusada
  add column if not exists estado        text not null default 'pendente',  -- pendente|aceite|descartada
  add column if not exists resolvida_em   timestamptz,
  add column if not exists resolvida_por  uuid,
  add column if not exists picagem_id     uuid;  -- picagem criada, se aceite

-- 2) Marca de correção manual na verificacao.
alter table public.verificacao
  add column if not exists correcao_manual boolean not null default false,
  add column if not exists criada_por      uuid;  -- admin que fez a correção (null = captura no dispositivo)

-- 3) Descartar uma recusa (sem criar picagem).
create or replace function public.descartar_recusa(p_recusa_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode = 'insufficient_privilege';
  end if;
  update public.picagem_recusada
     set estado = 'descartada', resolvida_em = now(), resolvida_por = auth.uid()
   where id = p_recusa_id
     and empresa_id = public.empresa_atual()
     and estado = 'pendente';
  if not found then
    raise exception 'recusa não encontrada ou já resolvida';
  end if;
end
$function$;

-- 4) Aceitar uma recusa -> cria picagem real (correção manual).
create or replace function public.aceitar_recusa(p_recusa_id uuid)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rec  record;
  v_vid  uuid := gen_random_uuid();
  v_pid  uuid;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode = 'insufficient_privilege';
  end if;

  select * into v_rec
    from public.picagem_recusada
   where id = p_recusa_id and empresa_id = public.empresa_atual()
   for update;

  if v_rec.id is null then
    raise exception 'recusa não encontrada';
  end if;
  if v_rec.estado <> 'pendente' then
    raise exception 'recusa já resolvida';
  end if;
  if v_rec.trabalhador_id is null then
    raise exception 'recusa sem trabalhador associado; não é possível aceitar';
  end if;

  -- Cria o registo como CORREÇÃO MANUAL: hora original, sem foto, atribuída ao admin.
  begin
    insert into public.verificacao
      (id, empresa_id, trabalhador_id, loja_id,
       momento_dispositivo, momento_servidor, foto_url,
       chave_idempotencia, autorizacao_offline, correcao_manual, criada_por)
    values
      (v_vid, v_rec.empresa_id, v_rec.trabalhador_id, v_rec.loja_id,
       v_rec.momento_dispositivo, now(), null,
       v_rec.chave_idempotencia, false, true, auth.uid());

    insert into public.picagem (empresa_id, verificacao_id, tipo)
    values (v_rec.empresa_id, v_vid, v_rec.tipo)
    returning id into v_pid;
  exception when unique_violation then
    -- já existia uma verificacao com esta chave (aceite em concorrência): liga e sai
    select p.id into v_pid
      from public.picagem p
      join public.verificacao v on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
     where v.empresa_id = v_rec.empresa_id and v.chave_idempotencia = v_rec.chave_idempotencia
     limit 1;
  end;

  update public.picagem_recusada
     set estado = 'aceite', resolvida_em = now(), resolvida_por = auth.uid(), picagem_id = v_pid
   where id = p_recusa_id;

  return json_build_object('picagem_id', v_pid, 'verificacao_id', v_vid);
end
$function$;

revoke all on function public.descartar_recusa(uuid) from public;
revoke all on function public.aceitar_recusa(uuid)   from public;
grant execute on function public.descartar_recusa(uuid) to authenticated;
grant execute on function public.aceitar_recusa(uuid)   to authenticated;

commit;
