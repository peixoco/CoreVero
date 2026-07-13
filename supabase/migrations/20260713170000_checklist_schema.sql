-- =====================================================================
-- 20260713170000_checklist_schema.sql — R2a: schema checklist_* (doc 13 §2)
--
-- Substitui o schema HACCP inicial (doc 01 §3.4, migração 20260625090000),
-- cujo versionamento por inteiro não congelava os itens — falha de auditoria
-- identificada em 2026-07-13 (doc 13). A Frente B nunca arrancou: as tabelas
-- antigas não têm dados de produção, pelo que são removidas e recriadas.
--
-- Conteúdo:
--   · drop das tabelas checklist_* antigas (e checklist_template_loja, que
--     o doc 13 não mantém — loja_id nullable no template cobre o caso);
--   · limite_legal — tabela de autoridade GLOBAL (sem empresa_id);
--   · checklist_template / _template_versao / _item / _instancia /
--     _resposta / acao_corretiva conforme doc 13 §2.2–2.7;
--   · RLS + policy admin_empresa em todas (exceto limite_legal);
--   · grants explícitos (invariante 6), incluindo grants de coluna na
--     versão: o estado NUNCA é alterável por roles de cliente — publicar
--     e arquivar passam obrigatoriamente pelas RPCs SECURITY DEFINER
--     (migração 20260713170100);
--   · seed de limite_legal: apenas Portaria 1135/95 (validada contra o
--     texto do DR). As linhas de cadeia de frio do Reg. 853/2004 NÃO são
--     semeadas: nenhum doc do repo traz os valores com atribuição expressa
--     à norma (divergência registada em docs/R2a-notas.md, decisão D2 —
--     valores AHRESP são código de boas práticas, não piso estatutário).
--
-- Notas transversais mantidas do schema base: PK uuid, created_at,
-- unique(empresa_id, id) + FKs compostas (referência cross-tenant
-- estruturalmente impossível), CHECKs nos conjuntos fechados.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Remoção do schema antigo (ordem: filhos primeiro)
-- ---------------------------------------------------------------------
drop table if exists acao_corretiva;
drop table if exists checklist_resposta;
drop table if exists checklist_instancia;
drop table if exists checklist_item;
drop table if exists checklist_template_loja;
drop table if exists checklist_template;

-- ---------------------------------------------------------------------
-- 2.1 limite_legal — tabela de autoridade (GLOBAL: sem empresa_id).
--     Leitura para authenticated; escrita só por migração (nenhum grant
--     de escrita a roles de cliente). Autoridade numérica futura da Vera.
-- ---------------------------------------------------------------------
create table limite_legal (
  id          uuid primary key default gen_random_uuid(),
  controlo    text not null unique,        -- ex. 'oleo_fritura_temperatura'
  descricao   text not null,
  norma       text not null,               -- ex. 'Portaria 1135/95'
  unidade     text not null,
  limite_min  numeric,                     -- estatutário
  limite_max  numeric,                     -- estatutário
  created_at  timestamptz not null default now(),
  constraint limite_legal_tem_limite check (limite_min is not null or limite_max is not null)
);

alter table limite_legal enable row level security;

create policy leitura_global on limite_legal
  for select to authenticated
  using (true);

revoke all on table limite_legal from public, anon, authenticated;
grant select on table limite_legal to authenticated;
grant select on table limite_legal to service_role;

-- ---------------------------------------------------------------------
-- 2.2 checklist_template — identidade (mutável, sem conteúdo)
-- ---------------------------------------------------------------------
create table checklist_template (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references empresa(id) on delete restrict,
  loja_id     uuid,                        -- null = template de empresa
  nome        text not null,
  ativo       bool not null default true,  -- desativar não apaga histórico
  created_at  timestamptz not null default now(),
  foreign key (empresa_id, loja_id) references loja(empresa_id, id) on delete restrict,
  unique (empresa_id, id)
);

-- ---------------------------------------------------------------------
-- 2.3 checklist_template_versao — o conteúdo versionado.
--     Um rascunho por template (índice único parcial); a imutabilidade de
--     publicada/arquivada é imposta por trigger na migração seguinte.
-- ---------------------------------------------------------------------
create table checklist_template_versao (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references empresa(id) on delete restrict,
  template_id       uuid not null,
  numero            int  not null constraint numero_positivo check (numero > 0),
  estado            text not null default 'rascunho'
                      check (estado in ('rascunho','publicada','arquivada')),
  frequencia_tipo   text not null
                      check (frequencia_tipo in ('diaria','por_turno','semanal','por_evento')),
  frequencia_config jsonb not null default '{}'::jsonb,
  publicada_em      timestamptz,
  created_at        timestamptz not null default now(),
  foreign key (empresa_id, template_id) references checklist_template(empresa_id, id) on delete restrict,
  unique (template_id, numero),
  unique (empresa_id, id)
);

-- um rascunho por template de cada vez (doc 13 §2.3)
create unique index um_rascunho_por_template
  on checklist_template_versao (empresa_id, template_id) where estado = 'rascunho';

-- hardening estrutural: nunca duas publicadas do mesmo template
-- (a RPC publicar_versao arquiva a anterior atomicamente)
create unique index uma_publicada_por_template
  on checklist_template_versao (empresa_id, template_id) where estado = 'publicada';

-- ---------------------------------------------------------------------
-- 2.4 checklist_item — pertence à VERSÃO (não ao template).
--     on delete cascade: apagar um rascunho leva os itens; versões
--     publicadas/arquivadas nunca chegam ao cascade (trigger BEFORE DELETE
--     na versão rejeita primeiro).
-- ---------------------------------------------------------------------
create table checklist_item (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references empresa(id) on delete restrict,
  versao_id         uuid not null,
  ordem             int  not null default 0,
  texto             text not null,
  tipo_resposta     text not null
                      check (tipo_resposta in ('numerico','booleano','texto','foto')),
  unidade           text,
  limite_min        numeric,
  limite_max        numeric,
  booleano_conforme bool default true,     -- false inverte ("sinais de pragas: sim" = não conforme)
  obrigatorio       bool not null default true,
  limite_fonte      text
                      check (limite_fonte in ('lei','codigo_boas_praticas','plano_estabelecimento')),
  limite_referencia text,                  -- ex. 'Portaria 1135/95', 'AHRESP CBP §x'
  limite_legal_id   uuid references limite_legal(id) on delete restrict,
  created_at        timestamptz not null default now(),
  foreign key (empresa_id, versao_id) references checklist_template_versao(empresa_id, id) on delete cascade,
  unique (empresa_id, id),
  -- limites numéricos só fazem sentido em itens numéricos
  constraint limites_so_numerico check (
    tipo_resposta = 'numerico' or (limite_min is null and limite_max is null)
  )
);

-- ---------------------------------------------------------------------
-- 2.5 checklist_instancia — congela por referência a conteúdo imutável
--     (versao_id substitui o antigo snapshot "template_versao int")
-- ---------------------------------------------------------------------
create table checklist_instancia (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresa(id) on delete restrict,
  template_id     uuid not null,
  versao_id       uuid not null,
  loja_id         uuid not null,
  verificacao_id  uuid,                    -- quem concluiu; null enquanto pendente/em_falta
  due_at          timestamptz,             -- null para por_evento
  estado          text not null default 'pendente'
                    check (estado in ('pendente','concluida','em_falta')),
  concluida_em    timestamptz,
  created_at      timestamptz not null default now(),
  foreign key (empresa_id, template_id)    references checklist_template(empresa_id, id)        on delete restrict,
  foreign key (empresa_id, versao_id)      references checklist_template_versao(empresa_id, id) on delete restrict,
  foreign key (empresa_id, loja_id)        references loja(empresa_id, id)                      on delete restrict,
  foreign key (empresa_id, verificacao_id) references verificacao(empresa_id, id)               on delete restrict,
  unique (empresa_id, id)
);

-- ---------------------------------------------------------------------
-- 2.6 checklist_resposta — conforme é escrito exclusivamente pela RPC
--     do servidor (R2b); nesta fase nenhum role de cliente escreve aqui.
-- ---------------------------------------------------------------------
create table checklist_resposta (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references empresa(id) on delete restrict,
  instancia_id  uuid not null,
  item_id       uuid not null,
  valor         text,                      -- representação canónica por tipo
  foto_url      text,                      -- retenção própria (relógio HACCP)
  conforme      bool not null,
  created_at    timestamptz not null default now(),
  foreign key (empresa_id, instancia_id) references checklist_instancia(empresa_id, id) on delete restrict,
  foreign key (empresa_id, item_id)      references checklist_item(empresa_id, id)      on delete restrict,
  unique (instancia_id, item_id),
  unique (empresa_id, id)
);

-- ---------------------------------------------------------------------
-- 2.7 acao_corretiva
-- ---------------------------------------------------------------------
create table acao_corretiva (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresa(id) on delete restrict,
  resposta_id     uuid not null,
  verificacao_id  uuid not null,           -- quem corrigiu, autenticado
  descricao       text not null,
  created_at      timestamptz not null default now(),
  foreign key (empresa_id, resposta_id)    references checklist_resposta(empresa_id, id) on delete restrict,
  foreign key (empresa_id, verificacao_id) references verificacao(empresa_id, id)        on delete restrict,
  unique (empresa_id, id)
);

-- ---------------------------------------------------------------------
-- Índices de apoio (unique(empresa_id,id) já indexa o prefixo empresa_id)
-- ---------------------------------------------------------------------
create index idx_versao_template   on checklist_template_versao (empresa_id, template_id);
create index idx_item_versao       on checklist_item (empresa_id, versao_id);
create index idx_item_limite_legal on checklist_item (limite_legal_id) where limite_legal_id is not null;
create index idx_instancia_estado  on checklist_instancia (empresa_id, loja_id, estado);
create index idx_instancia_versao  on checklist_instancia (empresa_id, versao_id);
create index idx_resposta_item     on checklist_resposta (empresa_id, item_id);
create index idx_acao_resposta     on acao_corretiva (empresa_id, resposta_id);

-- ---------------------------------------------------------------------
-- RLS — policy-tipo admin_empresa (padrão de 20260626100000).
-- Policies de kiosk (leitura de template publicado + preenchimento)
-- entram no R2b com o fluxo de preenchimento; nesta fase o kiosk não
-- vê checklists.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'checklist_template','checklist_template_versao','checklist_item',
    'checklist_instancia','checklist_resposta','acao_corretiva'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format($p$
      create policy admin_empresa on %I
        for all to authenticated
        using      (public.is_admin() and empresa_id = public.empresa_atual())
        with check (public.is_admin() and empresa_id = public.empresa_atual())
    $p$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Grants explícitos (invariante 6 — nada de default privileges).
-- O construtor edita templates, rascunhos e itens diretamente (RLS +
-- triggers protegem o que está congelado); instância/resposta/ação são
-- só-leitura para clientes até às RPCs do R2b.
-- ---------------------------------------------------------------------
revoke all on table checklist_template,
                    checklist_template_versao,
                    checklist_item,
                    checklist_instancia,
                    checklist_resposta,
                    acao_corretiva
  from public, anon, authenticated;

grant select, insert, update, delete on table checklist_template to authenticated;

-- item: UPDATE por coluna — versao_id e empresa_id ficam de fora, para um
-- item não poder ser "movido" entre rascunhos por DML direto (o trigger
-- da migração seguinte já trava versões não-rascunho; isto fecha o resto)
grant select, insert, delete on table checklist_item to authenticated;
grant update (ordem, texto, tipo_resposta, unidade, limite_min, limite_max,
              booleano_conforme, obrigatorio, limite_fonte, limite_referencia,
              limite_legal_id)
  on table checklist_item to authenticated;

-- versão: o ESTADO nunca é manipulável por cliente (grants de coluna).
-- Inserir → nasce 'rascunho' (default); publicar/arquivar → só via RPC
-- SECURITY DEFINER; apagar rascunhos é permitido (trigger trava o resto).
grant select on table checklist_template_versao to authenticated;
grant insert (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
  on table checklist_template_versao to authenticated;
grant update (frequencia_tipo, frequencia_config)
  on table checklist_template_versao to authenticated;
grant delete on table checklist_template_versao to authenticated;

grant select on table checklist_instancia to authenticated;
grant select on table checklist_resposta  to authenticated;
grant select on table acao_corretiva      to authenticated;

grant select, insert, update, delete on table checklist_template,
                                              checklist_template_versao,
                                              checklist_item,
                                              checklist_instancia,
                                              checklist_resposta,
                                              acao_corretiva
  to service_role;

-- ---------------------------------------------------------------------
-- Seed de limite_legal — Portaria 1135/95 (validada contra o texto do
-- Diário da República, n.º 214/1995, Série I-B de 1995-09-15):
--   n.º 1.º  — teor de compostos polares não superior a 25%;
--   n.os 2.º/3.º — temperatura da gordura/óleo não ultrapassa 180ºC.
-- Reg. 853/2004 (cadeia de frio): NÃO semeado — ver cabeçalho.
-- ---------------------------------------------------------------------
insert into limite_legal (controlo, descricao, norma, unidade, limite_min, limite_max) values
  ('oleo_fritura_temperatura',
   'Temperatura máxima da gordura ou óleo na fritura de géneros alimentícios',
   'Portaria 1135/95, n.os 2.º e 3.º', '°C', null, 180),
  ('oleo_fritura_compostos_polares',
   'Teor máximo de compostos polares em gorduras e óleos comestíveis usados em fritura',
   'Portaria 1135/95, n.º 1.º', '%', null, 25);
