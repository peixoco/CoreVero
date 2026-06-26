-- =====================================================================
-- 20260626110000_colaborador_detalhe.sql — Sprint 2
-- Separa identidade operacional (kiosk lê) de dados de RH (só admin).
--   · trabalhador        += pin (4 dígitos), area  -> legível pelo kiosk
--   · trabalhador_detalhe  = dados pessoais/RH      -> SÓ admin, nunca kiosk
-- =====================================================================

-- ---------------------------------------------------------------------
-- pin: 4 dígitos, atribuído (NÃO derivado de dados pessoais).
-- Nullable: o colaborador pode ser criado antes de lhe atribuir o pin.
-- É um fator fraco POR DESENHO — a prova de identidade é a foto da picagem.
-- (Plaintext aceitável no modelo de ameaça atual; hash fica como hardening
--  futuro, mas um pin de 4 dígitos é trivial de força-bruta com ou sem hash.)
-- ---------------------------------------------------------------------
alter table trabalhador add column pin text;
alter table trabalhador add constraint trabalhador_pin_4digitos
  check (pin is null or pin ~ '^[0-9]{4}$');

-- area operacional (cozinha/sala/copa/escritório...). Texto por agora;
-- deve graduar para lista controlada POR EMPRESA (config-as-data) quando
-- houver gestão de áreas — evita "cozinha" vs "Cozinha" vs "cozinha 1".
alter table trabalhador add column area text;

-- ---------------------------------------------------------------------
-- trabalhador_detalhe — dados pessoais/RH. 1:1 com trabalhador.
-- O KIOSK não tem policy aqui -> não lê estes dados (negado por omissão).
-- ---------------------------------------------------------------------
create table trabalhador_detalhe (
  trabalhador_id   uuid primary key,
  empresa_id       uuid not null references empresa(id) on delete restrict,
  nome_completo    text,
  data_nascimento  date,
  posicao          text,
  telefone         text,
  email            text,
  contrato_inicio  date,
  contrato_fim     date,
  created_at       timestamptz not null default now(),
  -- same-tenant: o detalhe pertence ao mesmo tenant que o trabalhador
  foreign key (empresa_id, trabalhador_id)
    references trabalhador(empresa_id, id) on delete cascade
);

create index on trabalhador_detalhe (empresa_id);

-- grant + RLS (a nova tabela não herda o grant do Sprint 0)
grant select, insert, update, delete on trabalhador_detalhe to authenticated;

alter table trabalhador_detalhe enable row level security;
create policy admin_empresa on trabalhador_detalhe
  for all to authenticated
  using      (public.is_admin() and empresa_id = public.empresa_atual())
  with check (public.is_admin() and empresa_id = public.empresa_atual());
-- (sem policy de kiosk: dados de RH ficam invisíveis ao kiosk)
