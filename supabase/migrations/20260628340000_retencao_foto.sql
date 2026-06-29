-- ============================================================================
-- Retenção da foto (Frente A / RGPD) — expira a foto sem tocar na prova de horas
-- ----------------------------------------------------------------------------
-- A foto de atribuição é dado pessoal: minimização RGPD obriga retenção CURTA.
-- A prova de horas (HACCP/laboral) tem retenção LONGA. Por isso separámos: a
-- foto é purgável independentemente. Este job, diário, apaga a foto expirada
-- (ficheiro REAL no Storage, via API) e anula `foto_url`. A picagem e as horas
-- ficam intactas (o trigger de imutabilidade só deixa mudar foto_url).
--
-- Retenção POR EMPRESA (o responsável pelo tratamento decide; configurável,
-- nunca cravada). Default 30 dias — placeholder a confirmar com jurista RGPD.
--
-- Apagar a linha em storage.objects por SQL deixaria o ficheiro órfão no S3.
-- A erradicação real faz-se pela API de Storage (DELETE), chamada daqui via
-- pg_net, com a service role key guardada no Vault (encriptada, nunca no git).
--
-- DEPOIS de aplicar esta migração, é preciso UM passo manual (uma vez):
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'service_role_key',
--                              'Service role para purga de fotos');
-- (a key está em Supabase → Settings → API → service_role. NÃO vai para o git.)
-- ============================================================================

begin;

create extension if not exists pg_net;

-- Retenção configurável por empresa.
alter table public.empresa
  add column if not exists retencao_foto_dias int not null default 30;

-- Job: apaga fotos expiradas (ficheiro + referência), sem tocar na prova.
create or replace function public.purgar_fotos_expiradas()
returns int
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_key  text;
  v_base text := 'https://xghfsudvpsgqkslobttj.supabase.co/storage/v1/object/picagens/';
  v_rec  record;
  v_n    int := 0;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'service_role_key';
  if v_key is null then
    raise exception 'Vault: segredo service_role_key em falta (ver cabeçalho da migração)';
  end if;

  for v_rec in
    select v.id, v.foto_url
      from public.verificacao v
      join public.empresa e on e.id = v.empresa_id
     where v.foto_url is not null
       and v.momento_servidor < now() - make_interval(days => e.retencao_foto_dias)
     limit 500
  loop
    -- apaga o ficheiro real no Storage (service role bypassa RLS)
    perform net.http_delete(
      url     => v_base || v_rec.foto_url,
      headers => jsonb_build_object('Authorization', 'Bearer ' || v_key)
    );
    -- anula a referência (trigger de imutabilidade permite só foto_url)
    update public.verificacao set foto_url = null where id = v_rec.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end
$function$;

-- Só o sistema corre isto (nunca o cliente).
revoke all on function public.purgar_fotos_expiradas() from public, authenticated, anon;

-- Agendamento diário às 03:30 (idempotente: remove antes de criar).
do $cron$
begin
  perform cron.unschedule('purgar-fotos');
exception when others then null;
end
$cron$;

select cron.schedule('purgar-fotos', '30 3 * * *', $$ select public.purgar_fotos_expiradas(); $$);

commit;
