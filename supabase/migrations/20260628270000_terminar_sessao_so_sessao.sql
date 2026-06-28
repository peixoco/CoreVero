-- ============================================================================
-- Correção: terminar_sessao_kiosk só termina a SESSÃO (não mexe no acesso)
-- ----------------------------------------------------------------------------
-- Revogar/Reativar = controlo de ACESSO (flag ativo).
-- Terminar sessão   = controlo de AUTENTICAÇÃO (sessão Auth).
-- São eixos independentes. A versão anterior misturava-os (punha ativo=false),
-- o que obrigava a um "reativar" extra após re-login. Aqui a função passa a
-- tocar APENAS na sessão; a flag ativo fica como estiver.
--
-- "Dispositivo perdido" = fazer as duas ações (Revogar + Terminar sessão).
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

  -- Verifica que o kiosk pertence à empresa do admin (sem alterar o acesso).
  if not exists (
    select 1 from public.kiosk k
     where k.id = p_kiosk_id and k.empresa_id = public.empresa_atual()
  ) then
    raise exception 'kiosk não encontrado nesta empresa';
  end if;

  -- Só a sessão Auth. A flag ativo NÃO é tocada.
  delete from auth.sessions where user_id = p_kiosk_id;
end
$function$;

revoke all on function public.terminar_sessao_kiosk(uuid) from public;
grant execute on function public.terminar_sessao_kiosk(uuid) to authenticated;

commit;
