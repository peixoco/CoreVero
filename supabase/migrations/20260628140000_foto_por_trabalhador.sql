-- ============================================================================
-- Foto por trabalhador: caminho {empresa}/{loja}/{trabalhador_id}/{verificacao_id}.jpg
-- ----------------------------------------------------------------------------
-- Porquê:
--   - Agrupa as fotos por colaborador dentro da loja (purga seletiva por
--     trabalhador = direito ao apagamento RGPD mais simples).
--   - Mantém TUDO em UUID (opaco, estável, único) — nada de nomes no caminho.
--   - O nome do ficheiro continua a ser o verificacao_id, por isso a garantia
--     anti-órfão (a policy extrai o id da última secção) mantém-se intacta.
--   - Endurece a policy: a foto tem de cair na pasta do trabalhador CERTO,
--     não só na loja certa.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Helper: a verificacao existe, é desta empresa/loja E deste trabalhador?
--    SECURITY DEFINER -> não exige SELECT em verificacao ao kiosk.
-- ----------------------------------------------------------------------------
create or replace function public.verificacao_do_trabalhador(
  p_verificacao_id uuid,
  p_trabalhador_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.verificacao v
    where v.id             = p_verificacao_id
      and v.trabalhador_id = p_trabalhador_id
      and v.empresa_id     = public.empresa_atual()
      and v.loja_id        = public.loja_atual()
  )
$function$;

revoke all on function public.verificacao_do_trabalhador(uuid, uuid) from public;
grant execute on function public.verificacao_do_trabalhador(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. registar_picagem — caminho passa a incluir a pasta do trabalhador.
--    Só muda a linha do v_path; o resto é igual.
-- ----------------------------------------------------------------------------
create or replace function public.registar_picagem(
  p_codigo_pessoal      text,
  p_pin                 text,
  p_tipo                text,
  p_momento_dispositivo timestamptz
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

  select id into v_trab
    from public.trabalhador
   where empresa_id     = v_empresa
     and codigo_pessoal = p_codigo_pessoal
     and ativo          = true
     and pin is not null
     and pin            = p_pin;

  if v_trab is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  -- caminho: {empresa}/{loja}/{trabalhador}/{verificacao_id}.jpg
  v_path := v_empresa::text || '/' || v_loja::text || '/'
            || v_trab::text || '/' || v_id::text || '.jpg';

  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id,
     momento_dispositivo, momento_servidor, foto_url)
  values
    (v_id, v_empresa, v_trab, v_loja,
     p_momento_dispositivo, now(), v_path);

  insert into public.picagem (empresa_id, verificacao_id, tipo)
  values (v_empresa, v_id, p_tipo);

  return json_build_object(
    'verificacao_id', v_id,
    'foto_path',      v_path
  );
end
$function$;

revoke all on function public.registar_picagem(text, text, text, timestamptz) from public;
grant execute on function public.registar_picagem(text, text, text, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Policy de upload — valida a pasta do trabalhador (foldername[3]) e que a
--    verificacao pertence a esse trabalhador. Mais apertada que a anterior.
--    Estrutura do name: empresa[1] / loja[2] / trabalhador[3] / id.jpg
-- ----------------------------------------------------------------------------
drop policy if exists kiosk_upload_picagens on storage.objects;

create policy kiosk_upload_picagens
on storage.objects
for insert
to authenticated
with check (
      bucket_id = 'picagens'
  and public.is_kiosk()
  and (storage.foldername(name))[1] = (public.empresa_atual())::text
  and (storage.foldername(name))[2] = (public.loja_atual())::text
  and public.verificacao_do_trabalhador(
        (split_part(storage.filename(name), '.', 1))::uuid,        -- verificacao_id
        ((storage.foldername(name))[3])::uuid                       -- trabalhador_id
      )
);

commit;
