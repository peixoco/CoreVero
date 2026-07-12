-- =====================================================================
-- 99_storage_stub_local.sql — APENAS PARA TESTE LOCAL.
-- No Supabase o schema 'storage' já existe (gerido pela plataforma).
-- Recriamos um stub mínimo para a migração de bucket/policies aplicar
-- num Postgres simples. NÃO replica o comportamento real do Storage.
-- =====================================================================
create schema if not exists storage;

create table if not exists storage.buckets (
  id     text primary key,
  name   text,
  public boolean default false
);

create table if not exists storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text,
  name      text,
  owner     uuid,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;

-- réplica simplificada de storage.foldername(): segmentos do caminho
-- excluindo o último (o nome do ficheiro).
create or replace function storage.foldername(name text)
returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1]
$$;

-- réplica simplificada de storage.filename(): o último segmento do caminho.
create or replace function storage.filename(name text)
returns text language sql immutable as $$
  select (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)]
$$;

grant usage on schema storage to anon, authenticated;
grant select, insert on storage.objects to authenticated;
