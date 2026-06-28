-- ============================================================================
-- Limpeza de bilhetes de autorização (Sprint 3b, ponto 4)
-- ----------------------------------------------------------------------------
-- A tabela `autorizacao` acumula bilhetes: usados (consumidos pela picagem) e
-- por-usar-mas-expirados (a picagem nunca completou). Nenhum serve depois de
-- usado/expirado. Este job apaga-os, com uma folga de 1 dia para depuração.
--
-- Mantém os bilhetes vivos (por usar, dentro da validade de 6h) intactos.
-- Corre via pg_cron, 1x/dia às 03:00.
--
-- Nota: se o `create extension pg_cron` falhar no push, ativa pg_cron primeiro
-- no Dashboard (Database > Extensions) e reaplica.
-- ============================================================================

begin;

create extension if not exists pg_cron;

create or replace function public.limpar_autorizacoes()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare n integer;
begin
  delete from public.autorizacao
   where (usada_em is not null and usada_em  < now() - interval '1 day')
      or (expira_em < now() - interval '1 day');
  get diagnostics n = row_count;
  return n;
end
$function$;

revoke all on function public.limpar_autorizacoes() from public;

-- Agendamento diário (03:00). cron.schedule é idempotente pelo nome do job.
select cron.schedule(
  'limpar-autorizacoes',
  '0 3 * * *',
  $$ select public.limpar_autorizacoes(); $$
);

commit;
