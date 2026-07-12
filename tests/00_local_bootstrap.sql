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
-- raw_app_meta_data é lido pela migração 20260628200000 (auto-população de kiosk).
create table if not exists auth.users (
  id                uuid primary key default gen_random_uuid(),
  email             text,
  raw_app_meta_data jsonb
);
alter table auth.users add column if not exists raw_app_meta_data jsonb;

-- Stub de auth.uid(): no Supabase lê o claim 'sub' do JWT verificado.
create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(
    coalesce(
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
      ''
    ), ''
  )::uuid
$$;

-- Stub de auth.sessions (terminar_sessao_kiosk faz delete aqui em runtime).
create table if not exists auth.sessions (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid
);

-- No Supabase o pgcrypto vive no schema 'extensions' (obter_cache_pins chama
-- extensions.hmac de forma qualificada). Num Postgres simples iria para public
-- e falharia em runtime — instala-se aqui no sítio certo.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
