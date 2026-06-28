-- ============================================================================
-- Terminar sessão de kiosk (Sprint 3b, ponto 2 — camada 2 do revogar)
-- ----------------------------------------------------------------------------
-- "Revogar" (camada 1) põe ativo=false: as RPCs recusam de imediato, mas a
-- sessão Auth do dispositivo continua viva (JWT stateless) — fica neutralizado,
-- mas reativável. É o "desativar temporário".
--
-- "Terminar sessão" (camada 2) é o "dispositivo perdido": além de ativo=false,
-- APAGA as sessões Auth do dispositivo. Sem refresh token válido, o tablet
-- perde a autenticação e NÃO volta sozinho — precisa de re-provisionamento
-- (novo login com as credenciais do kiosk). Para tablet roubado/perdido.
--
-- Nota honesta: nenhuma destas alcança um tablet OFFLINE. Esse caso é coberto
-- pela validade local da cache (TTL no cache-pin.ts), não por aqui.
--
-- Permissão: postgres tem DELETE em auth.sessions; a função é SECURITY DEFINER
-- (owner postgres), por isso apaga sem precisar de Edge Function nem service_role.
-- ============================================================================

begin;

create or replace function public.terminar_sessao_kiosk(p_kiosk_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem terminar sessões de kiosk'
      using errcode = 'insufficient_privilege';
  end if;

  -- Flag off + marca, restrito à empresa do admin (mesma regra do revogar_kiosk).
  update public.kiosk
     set ativo = false, revogado_em = now(), revogado_por = auth.uid()
   where id = p_kiosk_id and empresa_id = public.empresa_atual();
  if not found then
    raise exception 'kiosk não encontrado nesta empresa';
  end if;

  -- Mata as sessões Auth do dispositivo. Perde o refresh token -> não se
  -- re-autentica sozinho. (As sessões pertencem ao schema auth; o owner da
  -- função, postgres, tem permissão para as apagar.)
  delete from auth.sessions where user_id = p_kiosk_id;
end
$function$;

revoke all on function public.terminar_sessao_kiosk(uuid) from public;
grant execute on function public.terminar_sessao_kiosk(uuid) to authenticated;

commit;
