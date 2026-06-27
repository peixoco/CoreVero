-- Vista achatada para a listagem de picagens (e exports).
-- security_invoker = true -> respeita a RLS de quem consulta:
--   admin vê as picagens da sua empresa; kiosk vê 0 linhas.
-- Não expõe a coluna pin.
create or replace view public.vista_picagem
with (security_invoker = true) as
select
  p.id                  as picagem_id,
  p.empresa_id,
  p.tipo,
  v.id                  as verificacao_id,
  v.momento_dispositivo,
  v.momento_servidor,
  v.foto_url,
  v.loja_id,
  l.nome                as loja_nome,
  v.trabalhador_id,
  t.nome                as trabalhador_nome,
  t.codigo_pessoal
from public.picagem p
join public.verificacao v
  on v.empresa_id = p.empresa_id and v.id = p.verificacao_id
join public.loja l
  on l.empresa_id = v.empresa_id and l.id = v.loja_id
join public.trabalhador t
  on t.empresa_id = v.empresa_id and t.id = v.trabalhador_id;

grant select on public.vista_picagem to authenticated;