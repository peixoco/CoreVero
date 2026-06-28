-- ============================================================================
-- Recusas de picagem offline expostas ao admin (Sprint 3b, ponto 1)
-- ----------------------------------------------------------------------------
-- Uma picagem autorizada offline pode ser RECUSADA no drain (cache obsoleta:
-- trabalhador desativado/PIN mudado enquanto o tablet esteve offline). Nesse
-- caso NÃO há registo em verificacao/picagem — logo o admin não veria nada e a
-- picagem ficaria "perdida em silêncio" (doc 07 §1, o pior caso).
--
-- Solução: o kiosk, ao marcar um item como recusado (já online, pois o drain
-- correu), REPORTA a recusa para esta tabela. O admin passa a vê-las.
--
-- Isto NÃO é uma picagem válida — é o registo de uma tentativa rejeitada, para
-- atenção humana (o gestor confirma com o trabalhador o que aconteceu).
-- ============================================================================

begin;

create table if not exists public.picagem_recusada (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null,
  loja_id             uuid not null,
  trabalhador_id      uuid,                 -- conhecido da cache; sem FK (pode já não existir)
  codigo_pessoal      text,                 -- o que o kiosk tinha em cache
  tipo                text not null,
  momento_dispositivo timestamptz not null, -- hora do toque (offline)
  chave_idempotencia  uuid not null,        -- idempotência do report
  motivo              text not null,        -- mensagem do servidor no drain
  kiosk_id            uuid not null,
  criada_em           timestamptz not null default now(),
  constraint picagem_recusada_empresa_fk
    foreign key (empresa_id) references public.empresa (id),
  constraint picagem_recusada_loja_fk
    foreign key (empresa_id, loja_id) references public.loja (empresa_id, id),
  constraint picagem_recusada_idem
    unique (empresa_id, chave_idempotencia)
);

create index if not exists picagem_recusada_empresa_idx
  on public.picagem_recusada (empresa_id, criada_em desc);

alter table public.picagem_recusada enable row level security;

-- Admin lê as recusas da sua empresa (e loja, se âmbito loja).
drop policy if exists picagem_recusada_admin_select on public.picagem_recusada;
create policy picagem_recusada_admin_select on public.picagem_recusada
  for select to authenticated
  using (public.is_admin() and empresa_id = public.empresa_atual());

-- (Inserção é feita pela RPC SECURITY DEFINER abaixo; sem policy de insert para o kiosk.)

-- ----------------------------------------------------------------------------
-- RPC: o kiosk reporta uma recusa. Idempotente pela chave.
-- ----------------------------------------------------------------------------
create or replace function public.reportar_picagem_recusada(
  p_trabalhador_id      uuid,
  p_codigo_pessoal      text,
  p_tipo                text,
  p_momento_dispositivo timestamptz,
  p_chave_idempotencia  uuid,
  p_motivo              text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode reportar recusas'
      using errcode = 'insufficient_privilege';
  end if;
  -- nota: NÃO exigimos kiosk_ativo aqui — um kiosk revogado ainda deve poder
  -- reportar o que tinha pendente, para o gestor ver. Mas só da sua empresa/loja.
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida'
      using errcode = 'insufficient_privilege';
  end if;
  if p_chave_idempotencia is null then
    raise exception 'chave de idempotência em falta';
  end if;

  insert into public.picagem_recusada
    (empresa_id, loja_id, trabalhador_id, codigo_pessoal, tipo,
     momento_dispositivo, chave_idempotencia, motivo, kiosk_id)
  values
    (v_empresa, v_loja, p_trabalhador_id, p_codigo_pessoal, p_tipo,
     p_momento_dispositivo, p_chave_idempotencia, p_motivo, auth.uid())
  on conflict (empresa_id, chave_idempotencia) do nothing;
end
$function$;

revoke all on function public.reportar_picagem_recusada(uuid, text, text, timestamptz, uuid, text) from public;
grant execute on function public.reportar_picagem_recusada(uuid, text, text, timestamptz, uuid, text) to authenticated;

commit;
