-- =====================================================================
-- 20260626120000_picagem_intervalos.sql
-- Doc 06 §8.1: o registo legal de tempos (CT art. 202.º) exige registar
-- as INTERRUPÇÕES/pausas, não só entrada e saída — senão a picagem não
-- satisfaz o registo de tempos exigível pela ACT.
-- =====================================================================

-- substituir o CHECK do tipo (entrada/saida) por um que inclui intervalos
do $$
declare cname text;
begin
  select conname into cname
  from pg_constraint
  where conrelid = 'public.picagem'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%tipo%';
  if cname is not null then
    execute format('alter table public.picagem drop constraint %I', cname);
  end if;
end $$;

alter table picagem add constraint picagem_tipo_check
  check (tipo in ('entrada', 'saida', 'inicio_intervalo', 'fim_intervalo'));
