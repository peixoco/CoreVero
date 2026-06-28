-- ============================================================================
-- Picagem autorizada offline (Sprint 3b — lado servidor, parte 2)
-- ----------------------------------------------------------------------------
-- Online: iniciar_picagem valida o PIN e emite um bilhete (autorizacao);
--         registar_picagem consome o bilhete. O PIN foi verificado no servidor.
--
-- Offline: não há servidor para emitir bilhete. O kiosk valida o PIN localmente
--          (HMAC contra a cache) e afirma o trabalhador_id. registar_picagem_offline
--          aceita essa afirmação de um kiosk autenticado e não revogado, MAS:
--            - re-valida o trabalhador no momento do drain (apanha cache obsoleta:
--              trabalhador desativado ou PIN removido enquanto o tablet esteve
--              offline) -> se inválido, RECUSA com erro distinto, para o admin ver;
--            - marca a verificação como autorizacao_offline = true (menor garantia
--              que a online; auditável e distinguível no painel).
--
-- Modelo de confiança (Opção L, decidido): o PIN NUNCA viaja. A prova da picagem
-- offline é: kiosk autenticado + não revogado + foto (atribuição por revisão
-- humana). O PIN é fraco por desenho; a foto é a prova.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Flag de origem: distingue picagens autorizadas offline das online.
--    Default false -> registar_picagem (online) continua a inserir false sem
--    qualquer alteração.
-- ----------------------------------------------------------------------------
alter table public.verificacao
  add column if not exists autorizacao_offline boolean not null default false;

-- ----------------------------------------------------------------------------
-- 2. registar_picagem_offline
--    Assinatura paralela à registar_picagem, mas recebe trabalhador_id (afirmado
--    pelo kiosk) em vez de autorizacao_id (bilhete).
-- ----------------------------------------------------------------------------
create or replace function public.registar_picagem_offline(
  p_trabalhador_id      uuid,
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
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
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
  if p_trabalhador_id is null then
    raise exception 'trabalhador em falta';
  end if;

  -- Idempotência: já registada? devolve a existente (não duplica).
  select id, foto_url into v_exist_id, v_exist_path
    from public.verificacao
   where empresa_id = v_empresa
     and chave_idempotencia = p_chave_idempotencia;

  if v_exist_id is not null then
    return json_build_object(
      'verificacao_id', v_exist_id, 'foto_path', v_exist_path, 'repetida', true);
  end if;

  -- Re-validação no drain: apanha cache obsoleta. O trabalhador tem de ainda
  -- existir, pertencer à empresa, estar ativo e ter PIN. Se não, RECUSA — o
  -- cliente expõe esta recusa ao admin (picagem offline contra estado já mudado).
  select t.id into v_trab
    from public.trabalhador t
   where t.id         = p_trabalhador_id
     and t.empresa_id = v_empresa
     and t.ativo      = true
     and t.pin is not null;

  if v_trab is null then
    raise exception 'trabalhador inválido ou desativado (cache desatualizada)'
      using errcode = 'invalid_authorization_specification';
  end if;

  v_path := v_empresa::text || '/' || v_loja::text || '/'
            || v_trab::text || '/' || v_id::text || '.jpg';

  begin
    insert into public.verificacao
      (id, empresa_id, trabalhador_id, loja_id,
       momento_dispositivo, momento_servidor, foto_url,
       chave_idempotencia, autorizacao_offline)
    values
      (v_id, v_empresa, v_trab, v_loja,
       p_momento_dispositivo, now(), v_path,
       p_chave_idempotencia, true);

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

revoke all on function public.registar_picagem_offline(uuid, text, timestamptz, uuid) from public;
grant execute on function public.registar_picagem_offline(uuid, text, timestamptz, uuid) to authenticated;

commit;
