-- =====================================================================
-- 0001_schema.sql — Esquema completo (doc 01)
-- Sprint 0 · Fundações
--
-- Princípios aplicados:
--  · empresa_id em TODAS as tabelas de domínio (Princípio 2, doc 01 §1).
--    -> inclui checklist_item e checklist_template_loja, que o §3.4 omitia.
--       Sem isto, a policy destas tabelas exigiria um join — proibido pela
--       arquitetura ("um join falhado numa policy é uma fuga de dados").
--  · FKs compostas (empresa_id, id) na cadeia de prova: torna referências
--    cross-tenant estruturalmente impossíveis, não só barradas pela RLS.
--    (Hardening além do doc 01 — remover se for over-engineering p/ a fase.)
--  · PKs uuid; created_at em todas as tabelas; CHECKs nos conjuntos fechados.
-- =====================================================================

create extension if not exists pgcrypto;  -- gen_random_uuid() (core no PG13+, redundante mas inócuo)

-- ---------------------------------------------------------------------
-- 3.1 Tenancy e organização
-- ---------------------------------------------------------------------

-- empresa — o tenant. ÚNICA tabela sem empresa_id (ela é a fronteira).
create table empresa (
  id                         uuid primary key default gen_random_uuid(),
  nome                       text not null,
  plano                      text,                       -- referência ao plano Stripe (adiado)
  lojas_licenciadas          int  not null default 0,    -- limite de lojas pago
  colaboradores_licenciados  int  not null default 0,    -- limite de colaboradores ativos pago
  created_at                 timestamptz not null default now()
);

create table loja (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references empresa(id) on delete restrict,
  nome        text not null,
  ativa       bool not null default true,
  created_at  timestamptz not null default now(),
  unique (empresa_id, id)   -- alvo de FKs compostas same-tenant
);

create table trabalhador (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresa(id) on delete restrict,
  nome            text not null,
  codigo_pessoal  text not null,        -- único POR EMPRESA
  ativo           bool not null default true,
  created_at      timestamptz not null default now(),
  unique (empresa_id, codigo_pessoal),  -- doc 01 §3.1: "único por empresa"
  unique (empresa_id, id)
);

-- trabalhador_loja — afetação/escala (NÃO governa permissão de picagem).
create table trabalhador_loja (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresa(id) on delete restrict,
  trabalhador_id  uuid not null,
  loja_id         uuid not null,
  created_at      timestamptz not null default now(),
  foreign key (empresa_id, trabalhador_id) references trabalhador(empresa_id, id) on delete cascade,
  foreign key (empresa_id, loja_id)        references loja(empresa_id, id)        on delete cascade,
  unique (empresa_id, trabalhador_id, loja_id)
);

-- ---------------------------------------------------------------------
-- 3.2 Primitivo de verificação (quem + onde + quando + foto)
-- ---------------------------------------------------------------------
create table verificacao (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references empresa(id) on delete restrict,
  trabalhador_id      uuid not null,
  loja_id             uuid not null,            -- onde ocorreu
  momento_dispositivo timestamptz not null,     -- HORA AUTORITÁRIA (toque no dispositivo)
  momento_servidor    timestamptz not null default now(),  -- receção (auditoria/anti-fraude)
  foto_url            text,                     -- bucket UE; retenção curta (purgável; §6)
  created_at          timestamptz not null default now(),
  foreign key (empresa_id, trabalhador_id) references trabalhador(empresa_id, id) on delete restrict,
  foreign key (empresa_id, loja_id)        references loja(empresa_id, id)        on delete restrict,
  unique (empresa_id, id)
);

-- ---------------------------------------------------------------------
-- 3.3 Picagens
-- ---------------------------------------------------------------------
create table picagem (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresa(id) on delete restrict,
  verificacao_id  uuid not null,
  tipo            text not null check (tipo in ('entrada','saida')),
  created_at      timestamptz not null default now(),
  foreign key (empresa_id, verificacao_id) references verificacao(empresa_id, id) on delete restrict
);

-- ---------------------------------------------------------------------
-- 3.4 Checklists HACCP
-- ---------------------------------------------------------------------

-- checklist_template — vive na empresa; loja_id null = template da empresa.
create table checklist_template (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references empresa(id) on delete restrict,
  loja_id     uuid,                       -- null = template da empresa; preenchido = própria da loja
  nome        text not null,
  frequencia  text not null,              -- ex. 'diaria_2x', 'por_turno'
  versao      int  not null default 1,    -- incrementa a cada alteração (integridade de auditoria)
  ativo       bool not null default true,
  created_at  timestamptz not null default now(),
  -- FK composta nullable (MATCH SIMPLE): se loja_id null, não é verificada.
  foreign key (empresa_id, loja_id) references loja(empresa_id, id) on delete restrict,
  unique (empresa_id, id)
);

-- checklist_template_loja — atribui um template da empresa a lojas específicas.
-- empresa_id ADICIONADO (não estava no §3.4) para policy sem join.
create table checklist_template_loja (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references empresa(id) on delete restrict,
  template_id  uuid not null,
  loja_id      uuid not null,
  created_at   timestamptz not null default now(),
  foreign key (empresa_id, template_id) references checklist_template(empresa_id, id) on delete cascade,
  foreign key (empresa_id, loja_id)     references loja(empresa_id, id)               on delete cascade,
  unique (empresa_id, template_id, loja_id)
);

-- checklist_item — item tipado com limites críticos.
-- empresa_id ADICIONADO (não estava no §3.4) para policy sem join.
create table checklist_item (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references empresa(id) on delete restrict,
  template_id   uuid not null,
  ordem         int  not null default 0,
  texto         text not null,
  tipo_resposta text not null check (tipo_resposta in ('booleano','numerico','texto','foto')),
  unidade       text,                     -- ex. '°C'
  limite_min    numeric,                  -- limite crítico inferior
  limite_max    numeric,                  -- limite crítico superior
  created_at    timestamptz not null default now(),
  foreign key (empresa_id, template_id) references checklist_template(empresa_id, id) on delete cascade,
  unique (empresa_id, id)
);

-- checklist_instancia — um preenchimento concreto.
create table checklist_instancia (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references empresa(id) on delete restrict,
  template_id      uuid not null,
  template_versao  int  not null,         -- SNAPSHOT da versão usada (prova interpretável)
  loja_id          uuid not null,
  verificacao_id   uuid not null,         -- quem fez
  due_at           timestamptz,           -- quando devia ser feita (frequência)
  estado           text not null default 'pendente'
                     check (estado in ('pendente','concluida','em_falta')),
  created_at       timestamptz not null default now(),
  foreign key (empresa_id, template_id)    references checklist_template(empresa_id, id) on delete restrict,
  foreign key (empresa_id, loja_id)        references loja(empresa_id, id)               on delete restrict,
  foreign key (empresa_id, verificacao_id) references verificacao(empresa_id, id)        on delete restrict,
  unique (empresa_id, id)
);

create table checklist_resposta (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references empresa(id) on delete restrict,
  instancia_id uuid not null,
  item_id      uuid not null,
  valor        text,
  conforme     bool,                      -- calculado contra limite_min/max (app/edge)
  created_at   timestamptz not null default now(),
  foreign key (empresa_id, instancia_id) references checklist_instancia(empresa_id, id) on delete restrict,
  foreign key (empresa_id, item_id)      references checklist_item(empresa_id, id)      on delete restrict,
  unique (empresa_id, id)
);

-- acao_corretiva — obrigatória quando conforme = false.
create table acao_corretiva (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresa(id) on delete restrict,
  resposta_id     uuid not null,
  verificacao_id  uuid not null,          -- quem corrigiu (autenticado)
  descricao       text not null,
  created_at      timestamptz not null default now(),
  foreign key (empresa_id, resposta_id)    references checklist_resposta(empresa_id, id) on delete restrict,
  foreign key (empresa_id, verificacao_id) references verificacao(empresa_id, id)        on delete restrict
);

-- ---------------------------------------------------------------------
-- 3.5 Notificações (multi-canal, não acoplada ao WhatsApp)
-- ---------------------------------------------------------------------
create table notificacao (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references empresa(id) on delete restrict,
  origem_id     uuid,                     -- ex. checklist_resposta não conforme (uuid solto, sem FK por desenho)
  canal         text not null default 'email'
                  check (canal in ('email','in_app','whatsapp')),
  destinatario  text,                     -- configurável por loja
  estado        text not null default 'pendente'
                  check (estado in ('pendente','enviada','falhou')),
  tentativas    int  not null default 0,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3.6 Identidade e acesso (admins/gestores; colaboradores NÃO são users)
-- ---------------------------------------------------------------------
create table utilizador_app (
  id          uuid primary key references auth.users(id) on delete cascade,  -- = auth.users.id
  empresa_id  uuid not null references empresa(id) on delete restrict,       -- injetado no JWT (claim)
  ambito      text not null check (ambito in ('empresa','loja')),
  loja_id     uuid,                       -- obrigatório sse ambito='loja'
  created_at  timestamptz not null default now(),
  foreign key (empresa_id, loja_id) references loja(empresa_id, id) on delete restrict,
  -- coerência âmbito<->loja_id
  constraint ambito_loja_coerente check (
    (ambito = 'loja'    and loja_id is not null) or
    (ambito = 'empresa' and loja_id is null)
  )
);

-- ---------------------------------------------------------------------
-- Índices de apoio (RLS filtra por empresa_id; FKs precisam de índice).
-- unique(empresa_id,id) já indexa o prefixo empresa_id nessas tabelas.
-- ---------------------------------------------------------------------
create index on trabalhador_loja        (empresa_id);
create index on picagem                 (empresa_id, verificacao_id);
create index on checklist_template_loja (empresa_id, template_id);
create index on checklist_template_loja (empresa_id, loja_id);
create index on checklist_item          (empresa_id, template_id);
create index on checklist_instancia     (empresa_id, template_id);
create index on checklist_resposta      (empresa_id, instancia_id);
create index on checklist_resposta      (empresa_id, item_id);
create index on acao_corretiva          (empresa_id, resposta_id);
create index on notificacao             (empresa_id);
create index on utilizador_app          (empresa_id);
create index on verificacao             (empresa_id, trabalhador_id);
create index on verificacao             (empresa_id, loja_id);
