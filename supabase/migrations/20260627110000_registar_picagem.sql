-- (1) RPC registar_picagem (DEFINER): verifica PIN no servidor, insere
--     verificacao + picagem; empresa/loja vêm do JWT do kiosk.
create or replace function public.registar_picagem(
  p_verificacao_id     uuid,
  p_codigo_pessoal     text,
  p_pin                text,
  p_tipo               text,
  p_momento_dispositivo timestamptz,
  p_foto_url           text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    uuid;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens'
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
  if coalesce(p_foto_url, '') = '' then
    raise exception 'foto obrigatória';
  end if;

  select id into v_trab
  from public.trabalhador
  where empresa_id = v_empresa
    and codigo_pessoal = p_codigo_pessoal
    and ativo = true
    and pin is not null
    and pin = p_pin;

  if v_trab is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id,
     momento_dispositivo, momento_servidor, foto_url)
  values
    (p_verificacao_id, v_empresa, v_trab, v_loja,
     p_momento_dispositivo, now(), p_foto_url);

  insert into public.picagem (empresa_id, verificacao_id, tipo)
  values (v_empresa, p_verificacao_id, p_tipo);
end $$;

grant execute on function
  public.registar_picagem(uuid, text, text, text, timestamptz, text)
  to authenticated;

-- (2) Bucket privado para fotos de picagem
insert into storage.buckets (id, name, public)
values ('picagens', 'picagens', false)
on conflict (id) do nothing;

-- (3) Policies de storage. Caminho: {empresa_id}/{loja_id}/{verificacao_id}.jpg
drop policy if exists kiosk_upload_picagens on storage.objects;
create policy kiosk_upload_picagens on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'picagens'
    and public.is_kiosk()
    and (storage.foldername(name))[1] = public.empresa_atual()::text
    and (storage.foldername(name))[2] = public.loja_atual()::text
  );

drop policy if exists admin_read_picagens on storage.objects;
create policy admin_read_picagens on storage.objects
  for select to authenticated
  using (
    bucket_id = 'picagens'
    and public.is_admin()
    and (storage.foldername(name))[1] = public.empresa_atual()::text
  );