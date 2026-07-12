-- Acrescenta `desvio_segundos` a vista_picagem — desvio entre a hora do dispositivo
-- e a hora do servidor, para sinalização informativa no admin (R1).
-- A coluna é calculada (não armazenada) e é a última da lista para que o
-- CREATE OR REPLACE VIEW não quebre a ordem das colunas existentes.

begin;

create or replace view public.vista_picagem with (security_invoker=true) as
  select p.id as picagem_id, p.empresa_id, p.tipo,
    v.id as verificacao_id, v.momento_dispositivo, v.momento_servidor, v.foto_url,
    v.loja_id, l.nome as loja_nome, v.trabalhador_id, t.nome as trabalhador_nome, t.codigo_pessoal,
    p.anulada, p.motivo_anulacao, v.correcao_manual,
    extract(epoch from v.momento_servidor - v.momento_dispositivo)::int as desvio_segundos
  from public.picagem p
  join public.verificacao v on v.empresa_id=p.empresa_id and v.id=p.verificacao_id
  join public.loja l on l.empresa_id=v.empresa_id and l.id=v.loja_id
  join public.trabalhador t on t.empresa_id=v.empresa_id and t.id=v.trabalhador_id;

-- Invariante 6: grant explícito; nunca depender de default privileges.
grant select on public.vista_picagem to authenticated;

commit;
