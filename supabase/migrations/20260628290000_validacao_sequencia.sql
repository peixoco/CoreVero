-- ============================================================================
-- Validação dura de sequência de picagem (Frente A — camada servidor)
-- ----------------------------------------------------------------------------
-- Regras de transição (por trabalhador, por dia de Lisboa):
--   sem picagens / última = saída      -> só ENTRADA
--   última = entrada / fim_intervalo   -> SAÍDA ou INÍCIO_INTERVALO
--   última = inicio_intervalo          -> só FIM_INTERVALO
--
-- Online: registar_picagem recusa de imediato (o kiosk já só oferece opções
-- válidas). Offline: registar_picagem_offline recusa -> vira RECUSA gerível
-- pelo admin (aceitar/descartar), graças ao mecanismo de recusas. Nunca se
-- perde uma picagem em silêncio.
--
-- Correções manuais (aceitar_recusa) NÃO passam por aqui — o admin pode ter de
-- inserir fora de ordem para corrigir.
-- ============================================================================

begin;

-- Helper: a transição para p_tipo é válida dado o estado do trabalhador?
create or replace function public.sequencia_valida(
  p_empresa uuid, p_trabalhador uuid, p_tipo text, p_momento timestamptz)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_ultimo text;
begin
  select p.tipo into v_ultimo
    from public.picagem p
    join public.verificacao v
      on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
   where p.empresa_id = p_empresa
     and v.trabalhador_id = p_trabalhador
     and v.momento_dispositivo < p_momento
     and date_trunc('day', (v.momento_dispositivo at time zone 'Europe/Lisbon'))
       = date_trunc('day', (p_momento            at time zone 'Europe/Lisbon'))
   order by v.momento_dispositivo desc
   limit 1;

  return case
    when v_ultimo is null              then p_tipo = 'entrada'
    when v_ultimo in ('entrada','fim_intervalo') then p_tipo in ('saida','inicio_intervalo')
    when v_ultimo = 'inicio_intervalo' then p_tipo = 'fim_intervalo'
    when v_ultimo = 'saida'            then p_tipo = 'entrada'
    else false
  end;
end
$function$;

-- ----------------------------------------------------------------------------
-- registar_picagem (online) — com validação de sequência
-- ----------------------------------------------------------------------------
create or replace function public.registar_picagem(
  p_autorizacao_id uuid, p_tipo text,
  p_momento_dispositivo timestamptz, p_chave_idempotencia uuid)
returns json language plpgsql security definer set search_path to '' as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    uuid;
  v_id      uuid := gen_random_uuid();
  v_path    text;
  v_exist_id uuid; v_exist_path text;
  v_aut     record;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens' using errcode='insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor' using errcode='insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)' using errcode='insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento_dispositivo is null then raise exception 'momento do dispositivo em falta'; end if;
  if p_chave_idempotencia is null then raise exception 'chave de idempotência em falta'; end if;
  if p_autorizacao_id is null then raise exception 'autorização em falta'; end if;

  select id, foto_url into v_exist_id, v_exist_path
    from public.verificacao where empresa_id=v_empresa and chave_idempotencia=p_chave_idempotencia;
  if v_exist_id is not null then
    return json_build_object('verificacao_id',v_exist_id,'foto_path',v_exist_path,'repetida',true);
  end if;

  select * into v_aut from public.autorizacao
   where id=p_autorizacao_id and empresa_id=v_empresa and loja_id=v_loja for update;
  if v_aut.id is null then raise exception 'autorização inválida' using errcode='invalid_authorization_specification'; end if;
  if v_aut.usada_em is not null then raise exception 'autorização já utilizada' using errcode='invalid_authorization_specification'; end if;
  if v_aut.expira_em < now() then raise exception 'autorização expirada' using errcode='invalid_authorization_specification'; end if;

  v_trab := v_aut.trabalhador_id;

  -- VALIDAÇÃO DE SEQUÊNCIA
  if not public.sequencia_valida(v_empresa, v_trab, p_tipo, p_momento_dispositivo) then
    raise exception 'sequência de picagem inválida' using errcode='invalid_authorization_specification';
  end if;

  v_path := v_empresa::text||'/'||v_loja::text||'/'||v_trab::text||'/'||v_id::text||'.jpg';
  update public.autorizacao set usada_em=now() where id=p_autorizacao_id;

  begin
    insert into public.verificacao
      (id,empresa_id,trabalhador_id,loja_id,momento_dispositivo,momento_servidor,foto_url,chave_idempotencia)
    values (v_id,v_empresa,v_trab,v_loja,p_momento_dispositivo,now(),v_path,p_chave_idempotencia);
    insert into public.picagem (empresa_id,verificacao_id,tipo) values (v_empresa,v_id,p_tipo);
  exception when unique_violation then
    select id, foto_url into v_exist_id, v_exist_path
      from public.verificacao where empresa_id=v_empresa and chave_idempotencia=p_chave_idempotencia;
    return json_build_object('verificacao_id',v_exist_id,'foto_path',v_exist_path,'repetida',true);
  end;

  return json_build_object('verificacao_id',v_id,'foto_path',v_path,'repetida',false);
end
$function$;

-- ----------------------------------------------------------------------------
-- registar_picagem_offline — com validação de sequência (recusa vira gerível)
-- ----------------------------------------------------------------------------
create or replace function public.registar_picagem_offline(
  p_trabalhador_id uuid, p_tipo text,
  p_momento_dispositivo timestamptz, p_chave_idempotencia uuid)
returns json language plpgsql security definer set search_path to '' as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    uuid;
  v_id      uuid := gen_random_uuid();
  v_path    text;
  v_exist_id uuid; v_exist_path text;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens' using errcode='insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor' using errcode='insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)' using errcode='insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento_dispositivo is null then raise exception 'momento do dispositivo em falta'; end if;
  if p_chave_idempotencia is null then raise exception 'chave de idempotência em falta'; end if;
  if p_trabalhador_id is null then raise exception 'trabalhador em falta'; end if;

  select id, foto_url into v_exist_id, v_exist_path
    from public.verificacao where empresa_id=v_empresa and chave_idempotencia=p_chave_idempotencia;
  if v_exist_id is not null then
    return json_build_object('verificacao_id',v_exist_id,'foto_path',v_exist_path,'repetida',true);
  end if;

  select t.id into v_trab from public.trabalhador t
   where t.id=p_trabalhador_id and t.empresa_id=v_empresa and t.ativo=true and t.pin is not null;
  if v_trab is null then
    raise exception 'trabalhador inválido ou desativado (cache desatualizada)'
      using errcode='invalid_authorization_specification';
  end if;

  -- VALIDAÇÃO DE SEQUÊNCIA (offline: a recusa fica gerível pelo admin)
  if not public.sequencia_valida(v_empresa, v_trab, p_tipo, p_momento_dispositivo) then
    raise exception 'sequência de picagem inválida (offline)' using errcode='invalid_authorization_specification';
  end if;

  v_path := v_empresa::text||'/'||v_loja::text||'/'||v_trab::text||'/'||v_id::text||'.jpg';

  begin
    insert into public.verificacao
      (id,empresa_id,trabalhador_id,loja_id,momento_dispositivo,momento_servidor,foto_url,chave_idempotencia,autorizacao_offline)
    values (v_id,v_empresa,v_trab,v_loja,p_momento_dispositivo,now(),v_path,p_chave_idempotencia,true);
    insert into public.picagem (empresa_id,verificacao_id,tipo) values (v_empresa,v_id,p_tipo);
  exception when unique_violation then
    select id, foto_url into v_exist_id, v_exist_path
      from public.verificacao where empresa_id=v_empresa and chave_idempotencia=p_chave_idempotencia;
    return json_build_object('verificacao_id',v_exist_id,'foto_path',v_exist_path,'repetida',true);
  end;

  return json_build_object('verificacao_id',v_id,'foto_path',v_path,'repetida',false);
end
$function$;

commit;
