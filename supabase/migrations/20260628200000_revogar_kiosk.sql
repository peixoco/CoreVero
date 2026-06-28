-- ============================================================================
-- Revogar kiosk (Sprint 3b — pré-condição da cache de PIN offline)
-- ----------------------------------------------------------------------------
-- Porquê primeiro: o 3b mete HMACs dos PINs da loja em repouso num tablet
-- partilhado com o POS. Isso só é defensável se houver forma de MATAR o kiosk
-- de imediato. Como os JWT do Supabase são stateless (válidos até expirar,
-- ~1h, mesmo após ban), a revogação instantânea faz-se por um FLAG no servidor
-- que as RPCs e a policy de storage consultam a cada chamada.
--
-- Revogar = kiosk.ativo := false  ->  iniciar_picagem, registar_picagem e o
-- upload de fotos passam a ser recusados na hora. A cache offline fica inútil
-- (nada que produza consegue drenar).
--
-- Camada 2 (revogar a sessão Auth / refresh) precisa de service_role e fica
-- para uma Edge Function; o flag já fecha a ameaça do lado do servidor.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Registo de kiosks (1 linha por conta kiosk) + estado ativo/revogado
-- ----------------------------------------------------------------------------
create table if not exists public.kiosk (
  id           uuid primary key references auth.users(id) on delete cascade,
  empresa_id   uuid not null references public.empresa(id),
  loja_id      uuid not null,
  ativo        boolean not null default true,
  revogado_em  timestamptz,
  revogado_por uuid,
  created_at   timestamptz not null default now(),
  foreign key (empresa_id, loja_id) references public.loja (empresa_id, id)
);

alter table public.kiosk enable row level security;

drop policy if exists admin_empresa on public.kiosk;
create policy admin_empresa on public.kiosk
  for all
  using      (public.is_admin() and empresa_id = public.empresa_atual())
  with check (public.is_admin() and empresa_id = public.empresa_atual());

grant select, insert, update, delete on public.kiosk to authenticated;

-- Auto-popular a partir das contas kiosk já existentes (sem hardcode de ids).
-- Provisionamento futuro (Edge Function) deve inserir aqui ao criar a conta.
insert into public.kiosk (id, empresa_id, loja_id, ativo)
select u.id,
       (u.raw_app_meta_data->>'empresa_id')::uuid,
       (u.raw_app_meta_data->>'loja_id')::uuid,
       true
from auth.users u
where u.raw_app_meta_data->>'tipo' = 'kiosk'
  and u.raw_app_meta_data->>'empresa_id' is not null
  and u.raw_app_meta_data->>'loja_id' is not null
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 2. Helper: o kiosk que está a chamar está ativo?
--    SECURITY DEFINER -> não exige SELECT em kiosk ao próprio kiosk.
-- ----------------------------------------------------------------------------
create or replace function public.kiosk_ativo()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.kiosk k
    where k.id = auth.uid()
      and k.ativo
  )
$function$;

revoke all on function public.kiosk_ativo() from public;
grant execute on function public.kiosk_ativo() to authenticated;

-- ----------------------------------------------------------------------------
-- 3. RPCs de admin: revogar e reativar
-- ----------------------------------------------------------------------------
create or replace function public.revogar_kiosk(p_kiosk_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem revogar kiosks'
      using errcode = 'insufficient_privilege';
  end if;
  update public.kiosk
     set ativo = false, revogado_em = now(), revogado_por = auth.uid()
   where id = p_kiosk_id and empresa_id = public.empresa_atual();
  if not found then
    raise exception 'kiosk não encontrado nesta empresa';
  end if;
end
$function$;

create or replace function public.reativar_kiosk(p_kiosk_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem reativar kiosks'
      using errcode = 'insufficient_privilege';
  end if;
  update public.kiosk
     set ativo = true, revogado_em = null, revogado_por = null
   where id = p_kiosk_id and empresa_id = public.empresa_atual();
  if not found then
    raise exception 'kiosk não encontrado nesta empresa';
  end if;
end
$function$;

revoke all on function public.revogar_kiosk(uuid)  from public;
revoke all on function public.reativar_kiosk(uuid) from public;
grant execute on function public.revogar_kiosk(uuid)  to authenticated;
grant execute on function public.reativar_kiosk(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Guard nas três entradas do kiosk: iniciar, registar, upload.
--    (CREATE OR REPLACE reproduz a versão atual + a verificação kiosk_ativo.)
-- ----------------------------------------------------------------------------

create or replace function public.iniciar_picagem(
  p_codigo_pessoal text,
  p_pin            text
)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    record;
  v_ultima  record;
  v_aut     uuid := gen_random_uuid();
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode iniciar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;

  select t.id, t.nome
    into v_trab
    from public.trabalhador t
   where t.empresa_id     = v_empresa
     and t.codigo_pessoal = p_codigo_pessoal
     and t.ativo          = true
     and t.pin is not null
     and t.pin            = p_pin;

  if v_trab.id is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  insert into public.autorizacao (id, empresa_id, trabalhador_id, loja_id, expira_em)
  values (v_aut, v_empresa, v_trab.id, v_loja, now() + interval '6 hours');

  select p.tipo, v.momento_dispositivo
    into v_ultima
    from public.picagem p
    join public.verificacao v
      on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
   where p.empresa_id     = v_empresa
     and v.trabalhador_id = v_trab.id
     and v.momento_dispositivo >=
         (date_trunc('day', (now() at time zone 'Europe/Lisbon')) at time zone 'Europe/Lisbon')
   order by v.momento_dispositivo desc
   limit 1;

  return json_build_object(
    'autorizacao_id', v_aut,
    'trabalhador_id', v_trab.id,
    'nome',           v_trab.nome,
    'ultima_tipo',    v_ultima.tipo,
    'ultima_momento', v_ultima.momento_dispositivo
  );
end
$function$;

create or replace function public.registar_picagem(
  p_autorizacao_id      uuid,
  p_tipo                text,
  p_momento_dispositivo timestamptz,
  p_chave_idempotencia  uuid
)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    uuid;
  v_id      uuid := gen_random_uuid();
  v_path    text;
  v_exist_id   uuid;
  v_exist_path text;
  v_aut     record;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento_dispositivo is null then
    raise exception 'momento do dispositivo em falta';
  end if;
  if p_chave_idempotencia is null then
    raise exception 'chave de idempotência em falta';
  end if;
  if p_autorizacao_id is null then
    raise exception 'autorização em falta';
  end if;

  select id, foto_url into v_exist_id, v_exist_path
    from public.verificacao
   where empresa_id = v_empresa
     and chave_idempotencia = p_chave_idempotencia;

  if v_exist_id is not null then
    return json_build_object(
      'verificacao_id', v_exist_id, 'foto_path', v_exist_path, 'repetida', true);
  end if;

  select * into v_aut
    from public.autorizacao
   where id = p_autorizacao_id
     and empresa_id = v_empresa
     and loja_id    = v_loja
   for update;

  if v_aut.id is null then
    raise exception 'autorização inválida'
      using errcode = 'invalid_authorization_specification';
  end if;
  if v_aut.usada_em is not null then
    raise exception 'autorização já utilizada'
      using errcode = 'invalid_authorization_specification';
  end if;
  if v_aut.expira_em < now() then
    raise exception 'autorização expirada'
      using errcode = 'invalid_authorization_specification';
  end if;

  v_trab := v_aut.trabalhador_id;

  v_path := v_empresa::text || '/' || v_loja::text || '/'
            || v_trab::text || '/' || v_id::text || '.jpg';

  update public.autorizacao set usada_em = now() where id = p_autorizacao_id;

  begin
    insert into public.verificacao
      (id, empresa_id, trabalhador_id, loja_id,
       momento_dispositivo, momento_servidor, foto_url, chave_idempotencia)
    values
      (v_id, v_empresa, v_trab, v_loja,
       p_momento_dispositivo, now(), v_path, p_chave_idempotencia);

    insert into public.picagem (empresa_id, verificacao_id, tipo)
    values (v_empresa, v_id, p_tipo);

  exception when unique_violation then
    select id, foto_url into v_exist_id, v_exist_path
      from public.verificacao
     where empresa_id = v_empresa
       and chave_idempotencia = p_chave_idempotencia;
    return json_build_object(
      'verificacao_id', v_exist_id, 'foto_path', v_exist_path, 'repetida', true);
  end;

  return json_build_object(
    'verificacao_id', v_id, 'foto_path', v_path, 'repetida', false);
end
$function$;

revoke all on function public.iniciar_picagem(text, text) from public;
grant execute on function public.iniciar_picagem(text, text) to authenticated;
revoke all on function public.registar_picagem(uuid, text, timestamptz, uuid) from public;
grant execute on function public.registar_picagem(uuid, text, timestamptz, uuid) to authenticated;

-- policy de upload: + kiosk_ativo()
drop policy if exists kiosk_upload_picagens on storage.objects;
create policy kiosk_upload_picagens
on storage.objects
for insert
to authenticated
with check (
      bucket_id = 'picagens'
  and public.is_kiosk()
  and public.kiosk_ativo()
  and (storage.foldername(name))[1] = (public.empresa_atual())::text
  and (storage.foldername(name))[2] = (public.loja_atual())::text
  and public.verificacao_do_trabalhador(
        (split_part(storage.filename(name), '.', 1))::uuid,
        ((storage.foldername(name))[3])::uuid
      )
);

commit;
