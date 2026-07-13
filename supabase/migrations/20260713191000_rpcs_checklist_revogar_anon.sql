-- =====================================================================
-- 20260713191000_rpcs_checklist_revogar_anon.sql — R2a: fechar anon
--
-- As três RPCs do checklist (20260713170100 e 20260713190000) revogaram
-- EXECUTE de public mas não de anon — e no Supabase os default privileges
-- dão EXECUTE a anon nas funções novas (invariante 6: nunca depender de
-- default privileges). Detetado na verificação read-only pós-push; as
-- definer antigas já seguiam o padrão completo `from public, anon`
-- (ver 20260712150200).
--
-- Sem exploração prática (as três exigem is_admin() e claim de empresa),
-- mas o fecho é explícito, como manda a invariante.
-- =====================================================================

revoke all on function
  public.publicar_versao(uuid),
  public.criar_rascunho_de(uuid),
  public.instalar_templates_base()
  from public, anon;

grant execute on function
  public.publicar_versao(uuid),
  public.criar_rascunho_de(uuid),
  public.instalar_templates_base()
  to authenticated;
