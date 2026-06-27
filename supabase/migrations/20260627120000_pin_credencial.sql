-- O PIN passa a ser tratado como credencial: nenhum cliente (kiosk ou
-- admin) consegue LER a coluna pin diretamente. Só funções lhe tocam:
--   - registar_picagem (DEFINER) LÊ para verificar (a dona ignora o revoke)
--   - criar_colaborador / gerar_novo_pin ESCREVEM (INSERT/UPDATE não
--     precisam de SELECT) -> continuam INVOKER e funcionam.
-- Não dá para subtrair uma coluna de um grant de tabela: revoga-se o
-- SELECT de tabela e concede-se SELECT em todas as colunas EXCETO pin.
revoke select on public.trabalhador from authenticated;

grant select
  (id, empresa_id, nome, codigo_pessoal, ativo, created_at, area)
  on public.trabalhador
  to authenticated;