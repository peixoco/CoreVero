-- =====================================================================
-- 00_local_bootstrap.sql — APENAS PARA TESTE LOCAL.
-- No Supabase estes objetos já existem (geridos pela plataforma):
-- os roles anon/authenticated/service_role e o schema auth + auth.users.
-- Recriamo-los aqui para correr as migrações num Postgres simples.
-- =====================================================================
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon')
    then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated')
    then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role')
    then create role service_role nologin noinherit bypassrls; end if;
end $$;

create schema if not exists auth;

-- Stub mínimo de auth.users (no Supabase tem muitas mais colunas).
create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text
);
