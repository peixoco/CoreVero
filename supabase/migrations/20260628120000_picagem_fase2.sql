-- ============================================================================
-- Fase 2 do kiosk — picagem com câmara, sem fotos órfãs
-- ----------------------------------------------------------------------------
-- Modelo de garantia (Opção X):
--   1) iniciar_picagem  -> verifica PIN; NÃO escreve. A câmara só abre com
--      código+PIN corretos (ponto 2 do Pedro + minimização RGPD).
--   2) registar_picagem -> gera verificacao_id NO SERVIDOR, insere
--      verificacao+picagem, devolve {verificacao_id, foto_path}. Já não recebe
--      verificacao_id nem foto_url do cliente.
--   3) upload da foto -> a policy de storage exige que a verificacao já exista
--      para aquele caminho => FOTO ÓRFÃ É IMPOSSÍVEL POR RLS.
--
-- Nota: o kiosk só tem INSERT em verificacao (kiosk_insert), não tem SELECT.
-- Por isso o EXISTS da policy de upload passa por um helper SECURITY DEFINER,
-- em vez de abrir SELECT ao kiosk (mantém a superfície mínima — doc 01 §4).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Helper: a verificacao existe e é desta empresa/loja?
--    SECURITY DEFINER -> vê a linha sem o kiosk precisar de SELECT em verificacao.
--    O scope (empresa/loja) vem do JWT do CHAMADOR (request.jwt.claims é um GUC
--    de request, não afetado pelo SECURITY DEFINER).
-- ----------------------------------------------------------------------------
create or replace function public.verificacao_pertence_kiosk(p_verificacao_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.verificacao v
    where v.id = p_verificacao_id
      and v.empresa_id = public.empresa_atual()
      and v.loja_id    = public.loja_atual()
  )
$function$;

revoke all on function public.verificacao_pertence_kiosk(uuid) from public;
grant execute on function public.verificacao_pertence_kiosk(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. iniciar_picagem — verifica PIN no servidor; NÃO escreve nada.
--    Devolve nome + última picagem de HOJE (para o kiosk sugerir o próximo tipo).
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

  -- última picagem de hoje (qualquer loja da empresa), hora local de Lisboa
  select p.tipo, v.momento_dispositivo
    into v_ultima
    from public.picagem p
    join public.verificacao v
      on v.id = p.verificacao_id
     and v.empresa_id = p.empresa_id
   where p.empresa_id      = v_empresa
     and v.trabalhador_id  = v_trab.id
     and v.momento_dispositivo >=
         (date_trunc('day', (now() at time zone 'Europe/Lisbon')) at time zone 'Europe/Lisbon')
   order by v.momento_dispositivo desc
   limit 1;

  return json_build_object(
    'trabalhador_id', v_trab.id,
    'nome',           v_trab.nome,
    'ultima_tipo',    v_ultima.tipo,            -- null se ainda não picou hoje
    'ultima_momento', v_ultima.momento_dispositivo
  );
end
$function$;

revoke all on function public.iniciar_picagem(text, text) from public;
grant execute on function public.iniciar_picagem(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. registar_picagem — assinatura NOVA (sem verificacao_id, sem foto_url).
--    Gera o id no servidor e devolve o caminho determinístico da foto.
-- ----------------------------------------------------------------------------
drop function if exists public.registar_picagem(uuid, text, text, text, timestamptz, text);

create or replace function public.registar_picagem(
  p_codigo_pessoal      text,
  p_pin                 text,
  p_tipo                text,
  p_momento_dispositivo timestamptz
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

  select id into v_trab
    from public.trabalhador
   where empresa_id     = v_empresa
     and codigo_pessoal = p_codigo_pessoal
     and ativo          = true
     and pin is not null
     and pin            = p_pin;

  if v_trab is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  -- caminho determinístico: {empresa}/{loja}/{verificacao_id}.jpg
  v_path := v_empresa::text || '/' || v_loja::text || '/' || v_id::text || '.jpg';

  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id,
     momento_dispositivo, momento_servidor, foto_url)
  values
    (v_id, v_empresa, v_trab, v_loja,
     p_momento_dispositivo, now(), v_path);

  insert into public.picagem (empresa_id, verificacao_id, tipo)
  values (v_empresa, v_id, p_tipo);

  return json_build_object(
    'verificacao_id', v_id,
    'foto_path',      v_path
  );
end
$function$;

revoke all on function public.registar_picagem(text, text, text, timestamptz) from public;
grant execute on function public.registar_picagem(text, text, text, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Policy de upload apertada — só deixa escrever onde a verificacao já existe.
--    Esta é a garantia "zero fotos órfãs".
-- ----------------------------------------------------------------------------
drop policy if exists kiosk_upload_picagens on storage.objects;

create policy kiosk_upload_picagens
on storage.objects
for insert
to authenticated
with check (
      bucket_id = 'picagens'
  and public.is_kiosk()
  and (storage.foldername(name))[1] = (public.empresa_atual())::text
  and (storage.foldername(name))[2] = (public.loja_atual())::text
  and public.verificacao_pertence_kiosk(
        (split_part(storage.filename(name), '.', 1))::uuid
      )
);

commit;

-- ============================================================================
-- Verificação manual (correr separadamente, NÃO faz parte da migração):
--   -- como kiosk, um upload para um id inexistente tem de FALHAR;
--   -- um upload para o caminho devolvido por registar_picagem tem de PASSAR.
-- ============================================================================
