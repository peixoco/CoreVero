-- =====================================================================
-- 20260626100000_identidade_acesso.sql — Sprint 1 (parcial)
-- Identidade por tipo (admin/kiosk) + RLS diferenciada.
--
-- Substitui a policy uniforme do Sprint 0 (que dava a QUALQUER authenticated
-- acesso a toda a empresa) por:
--   · admin-empresa : acesso total à sua empresa (FOR ALL)
--   · kiosk         : SÓ INSERÇÃO de eventos da sua loja + leitura fina
--
-- admin-loja: ADIADO de propósito (precisa de denormalizar loja_id para
-- picagem/checklist_resposta/acao_corretiva; sem caso multi-loja real,
-- evita-se adivinhar a semântica). Na fase de teste todos os admins são
-- admin-empresa.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers de identidade (lêem app_metadata do JWT verificado)
-- ---------------------------------------------------------------------
create or replace function public.jwt_app_meta()
returns jsonb language sql stable set search_path = '' as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata'
$$;

-- empresa_atual() reescrita para passar por jwt_app_meta() (comportamento idêntico)
create or replace function public.empresa_atual()
returns uuid language sql stable set search_path = '' as $$
  select nullif(public.jwt_app_meta() ->> 'empresa_id', '')::uuid
$$;

create or replace function public.loja_atual()
returns uuid language sql stable set search_path = '' as $$
  select nullif(public.jwt_app_meta() ->> 'loja_id', '')::uuid
$$;

create or replace function public.is_admin()
returns boolean language sql stable set search_path = '' as $$
  select coalesce(public.jwt_app_meta() ->> 'tipo', '') = 'admin'
$$;

create or replace function public.is_kiosk()
returns boolean language sql stable set search_path = '' as $$
  select coalesce(public.jwt_app_meta() ->> 'tipo', '') = 'kiosk'
$$;

grant execute on function
  public.jwt_app_meta(), public.loja_atual(), public.is_admin(), public.is_kiosk()
  to authenticated, anon;

-- ---------------------------------------------------------------------
-- Substituir a policy uniforme do Sprint 0 pela policy de ADMIN-EMPRESA.
-- Sem o is_admin(), o kiosk continuaria a apanhar esta policy e leria
-- toda a empresa — é a razão de a alterarmos antes de adicionar o kiosk.
-- ---------------------------------------------------------------------
drop policy tenant_isolation on empresa;
create policy admin_empresa on empresa
  for all to authenticated
  using      (public.is_admin() and id = public.empresa_atual())
  with check (public.is_admin() and id = public.empresa_atual());

do $$
declare t text;
begin
  foreach t in array array[
    'loja','trabalhador','trabalhador_loja','verificacao','picagem',
    'checklist_template','checklist_template_loja','checklist_item',
    'checklist_instancia','checklist_resposta','acao_corretiva',
    'notificacao','utilizador_app'
  ]
  loop
    execute format('drop policy tenant_isolation on %I;', t);
    execute format($f$
      create policy admin_empresa on %I
        for all to authenticated
        using      (public.is_admin() and empresa_id = public.empresa_atual())
        with check (public.is_admin() and empresa_id = public.empresa_atual());
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- KIOSK — INSERÇÃO de eventos da sua loja.
-- Tabelas com loja_id próprio: força loja_id = loja_atual().
-- Tabelas sem loja_id (picagem/resposta/acao): força empresa (mesma empresa).
--   [gap conhecido, baixa severidade: dentro da MESMA empresa, um kiosk
--    poderia anexar um filho ao pai de outra loja. Fecha-se com loja_id
--    denormalizado quando houver kiosks de várias lojas em simultâneo.]
-- ---------------------------------------------------------------------
create policy kiosk_insert on verificacao
  for insert to authenticated
  with check (public.is_kiosk() and empresa_id = public.empresa_atual() and loja_id = public.loja_atual());

create policy kiosk_insert on checklist_instancia
  for insert to authenticated
  with check (public.is_kiosk() and empresa_id = public.empresa_atual() and loja_id = public.loja_atual());

create policy kiosk_insert on picagem
  for insert to authenticated
  with check (public.is_kiosk() and empresa_id = public.empresa_atual());

create policy kiosk_insert on checklist_resposta
  for insert to authenticated
  with check (public.is_kiosk() and empresa_id = public.empresa_atual());

create policy kiosk_insert on acao_corretiva
  for insert to authenticated
  with check (public.is_kiosk() and empresa_id = public.empresa_atual());

-- ---------------------------------------------------------------------
-- KIOSK — LEITURA FINA (só o necessário para capturar; nunca gestão).
-- A sua loja; trabalhadores ATIVOS da empresa (picam em qualquer loja);
-- templates/itens ativos aplicáveis. NÃO lê histórico nem gestão.
-- ---------------------------------------------------------------------
create policy kiosk_read on loja
  for select to authenticated
  using (public.is_kiosk() and id = public.loja_atual());

create policy kiosk_read on trabalhador
  for select to authenticated
  using (public.is_kiosk() and empresa_id = public.empresa_atual() and ativo);

create policy kiosk_read on checklist_template
  for select to authenticated
  using (public.is_kiosk() and empresa_id = public.empresa_atual() and ativo
         and (loja_id is null or loja_id = public.loja_atual()));

create policy kiosk_read on checklist_item
  for select to authenticated
  using (public.is_kiosk() and empresa_id = public.empresa_atual());

create policy kiosk_read on checklist_template_loja
  for select to authenticated
  using (public.is_kiosk() and empresa_id = public.empresa_atual() and loja_id = public.loja_atual());

-- NOTA: sem policy de kiosk para empresa, utilizador_app, notificacao,
-- trabalhador_loja, e SEM select em verificacao/picagem/instancia/resposta/
-- acao -> o kiosk NÃO lê histórico nem dados de gestão (negado por omissão).
-- UPDATE/DELETE pelo kiosk: nenhuma policy -> negado (append-only de facto).
