-- ============================================================================
-- Cache de PIN para autorização offline (Sprint 3b — lado servidor)
-- ----------------------------------------------------------------------------
-- Saída 1 com chave POR DISPOSITIVO:
--   - cada kiosk gera uma chave no Keychain e regista-a (registar_chave_kiosk).
--   - o servidor calcula, por trabalhador ativo da loja, HMAC(codigo:pin) com a
--     chave DAQUELE kiosk e devolve só o HMAC (obter_cache_pins). NUNCA o PIN.
--   - offline, o kiosk recalcula o HMAC do código+PIN digitado (tem a chave no
--     Keychain) e compara. Bate -> câmara abre.
--
-- Modelo de ameaça (assumido, no log de decisões):
--   - HMAC de PIN de 4 dígitos é fraco (10 000 combinações). NÃO é a segurança.
--   - A segurança é o CONJUNTO: chave no Keychain (cache extraída sozinha é
--     inútil) + foto é a prova + revogar kiosk.
--   - Servidor comprometido = tudo perdido, mas já era (tem os PINs). A chave ao
--     lado não piora esse cenário; protege o caso real: tablet roubado.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Material da chave do dispositivo (hex). Nullable: kiosks antigos não têm
--    até registarem. Só o próprio kiosk a escreve (via RPC SECURITY DEFINER).
-- ----------------------------------------------------------------------------
alter table public.kiosk
  add column if not exists chave_hmac text,
  add column if not exists chave_registada_em timestamptz;

-- ----------------------------------------------------------------------------
-- 2. registar_chave_kiosk — o kiosk regista a SUA chave (uma vez / rotação).
--    auth.uid() = id do kiosk; só pode escrever a própria linha.
-- ----------------------------------------------------------------------------
create or replace function public.registar_chave_kiosk(p_chave_hex text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare v_id uuid := auth.uid();
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar a sua chave'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if p_chave_hex is null or length(p_chave_hex) < 32 then
    raise exception 'chave inválida';
  end if;

  update public.kiosk
     set chave_hmac = p_chave_hex, chave_registada_em = now()
   where id = v_id;
  if not found then
    raise exception 'kiosk não registado';
  end if;
end
$function$;

revoke all on function public.registar_chave_kiosk(text) from public;
grant execute on function public.registar_chave_kiosk(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. obter_cache_pins — devolve a cache para o kiosk que chama.
--    Por trabalhador ativo da loja: codigo, nome, trabalhador_id e
--    HMAC(codigo:pin) com a chave DESTE kiosk. NUNCA o PIN em claro.
--    A coluna pin é lida aqui porque a função é SECURITY DEFINER (o kiosk
--    continua sem SELECT direto na coluna).
-- ----------------------------------------------------------------------------
create or replace function public.obter_cache_pins()
returns table (
  codigo_pessoal text,
  nome           text,
  trabalhador_id uuid,
  pin_hmac       text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_chave   text;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode obter a cache'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida'
      using errcode = 'insufficient_privilege';
  end if;

  select k.chave_hmac into v_chave
    from public.kiosk k where k.id = auth.uid();
  if v_chave is null then
    raise exception 'chave do dispositivo não registada';
  end if;

  return query
    select t.codigo_pessoal,
           t.nome,
           t.id,
           encode(
             extensions.hmac(t.codigo_pessoal || ':' || t.pin, v_chave, 'sha256'),
             'hex'
           ) as pin_hmac
    from public.trabalhador t
   where t.empresa_id = v_empresa
     and t.ativo = true
     and t.pin is not null;
end
$function$;

revoke all on function public.obter_cache_pins() from public;
grant execute on function public.obter_cache_pins() to authenticated;

commit;
