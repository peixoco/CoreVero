-- P2 (doc 09 v2): picagem_recusada funcionava via default privileges legados
-- (anon e authenticated com ALL, incluindo DELETE/TRUNCATE), que a Supabase torna
-- always-revoked em 2026-10-30. Verificado na BD: todas as escritas em picagem_recusada
-- passam por RPCs SECURITY DEFINER (reportar_picagem_recusada, descartar_recusa,
-- aceitar_recusa), portanto os roles de cliente só precisam de SELECT.
--
-- Também verificado: anon tem grants amplos em trabalhador (incluindo SELECT na coluna
-- pin) sem nenhuma policy RLS que lhe dê acesso — privilégio morto, revogado por inteiro.
--
-- NOTA — o que esta migração NÃO faz (deliberado):
-- authenticated mantém INSERT/UPDATE na coluna trabalhador.pin porque criar_colaborador
-- e gerar_novo_pin são SECURITY INVOKER e dependem desses grants. Fechar isso exige
-- convertê-las para SECURITY DEFINER (com verificação interna de empresa), a fazer
-- junto com o P4 (reanexar edição de colaborador). Registado no doc 09 v2.

-- picagem_recusada: cortar tudo e repor só o necessário
revoke all on table public.picagem_recusada from anon;
revoke all on table public.picagem_recusada from authenticated;
grant select on table public.picagem_recusada to authenticated;

-- trabalhador: anon não tem policy nenhuma nem uso legítimo (o kiosk é authenticated)
revoke all on table public.trabalhador from anon;
