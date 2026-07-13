-- =====================================================================
-- seed.sql — Dados de arranque (Supabase: supabase/seed.sql)
-- Empresa A = o restaurante próprio (fase de teste).
-- Empresa B = tenant mínimo, existe SÓ para provar isolamento.
-- Corre como superuser/service_role -> bypassa RLS (insere nos dois tenants).
-- NÃO insere utilizador_app/auth.users (geridos pelo Auth, não por SQL).
-- UUIDs fixos para o teste de isolamento poder referenciá-los.
-- =====================================================================

-- ============================ EMPRESA A ==============================
insert into empresa (id, nome, plano, lojas_licenciadas, colaboradores_licenciados) values
  ('11111111-1111-1111-1111-111111111111', 'Restaurante Piloto, Lda.', 'teste', 5, 25);

insert into loja (id, empresa_id, nome, ativa) values
  ('a1100000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Cozinha Central', true),
  ('a1100000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Esplanada',       true);

insert into trabalhador (id, empresa_id, nome, codigo_pessoal, ativo) values
  ('a1200000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Ana Sousa',  '1001', true),
  ('a1200000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Bruno Lima', '1002', true);

-- afetação (escala) — não governa permissão de picagem
insert into trabalhador_loja (empresa_id, trabalhador_id, loja_id) values
  ('11111111-1111-1111-1111-111111111111', 'a1200000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001');

-- prova: uma verificação + a respetiva picagem de entrada
insert into verificacao (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, foto_url) values
  ('a1300000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'a1200000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001',
   now() - interval '2 hours', 'fotos/a/entrada-ana.jpg');

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('11111111-1111-1111-1111-111111111111', 'a1300000-0000-0000-0000-000000000001', 'entrada');

-- checklist (schema versionado do doc 13) — configurado pelo admin, não em código.
-- A versão nasce rascunho, recebe itens e só depois é publicada (o trigger de
-- imutabilidade bloqueia INSERT de itens em versões já publicadas).
insert into checklist_template (id, empresa_id, loja_id, nome, ativo) values
  ('a1400000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', null,
   'Temperaturas de frio', true);

insert into checklist_template_versao (id, empresa_id, template_id, numero, frequencia_tipo, frequencia_config) values
  ('a1410000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'a1400000-0000-0000-0000-000000000001', 1, 'diaria', '{"vezes_por_dia":2,"janelas":["08:00","16:00"]}');

insert into checklist_item (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade, limite_min, limite_max, limite_fonte, limite_referencia) values
  ('11111111-1111-1111-1111-111111111111', 'a1410000-0000-0000-0000-000000000001', 1,
   'Temperatura do frigorífico 1', 'numerico', '°C', 0, 5, 'plano_estabelecimento', 'Plano HACCP do estabelecimento'),
  ('11111111-1111-1111-1111-111111111111', 'a1410000-0000-0000-0000-000000000001', 2,
   'Temperatura da arca congeladora', 'numerico', '°C', null, -18, 'plano_estabelecimento', 'Plano HACCP do estabelecimento');

update checklist_template_versao
   set estado = 'publicada', publicada_em = now()
 where id = 'a1410000-0000-0000-0000-000000000001';

-- ============================ EMPRESA B ==============================
-- Tenant de isolamento (só para o teste). Dados mínimos.
insert into empresa (id, nome, plano, lojas_licenciadas, colaboradores_licenciados) values
  ('22222222-2222-2222-2222-222222222222', 'Tenant Isolamento (teste)', 'teste', 1, 5);

insert into loja (id, empresa_id, nome, ativa) values
  ('b2100000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Loja B', true);

insert into trabalhador (id, empresa_id, nome, codigo_pessoal, ativo) values
  ('b2200000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Carlos B', '1001', true);
  -- nota: codigo_pessoal '1001' repete o da Empresa A de propósito —
  -- é único POR empresa, não global. Prova a desnormalização do tenant.

insert into verificacao (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo) values
  ('b2300000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'b2200000-0000-0000-0000-000000000001', 'b2100000-0000-0000-0000-000000000001', now() - interval '1 hour');

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('22222222-2222-2222-2222-222222222222', 'b2300000-0000-0000-0000-000000000001', 'entrada');

insert into checklist_template (id, empresa_id, loja_id, nome, ativo) values
  ('b2400000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', null,
   'Higiene pessoal', true);

insert into checklist_template_versao (id, empresa_id, template_id, numero, frequencia_tipo, frequencia_config) values
  ('b2410000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'b2400000-0000-0000-0000-000000000001', 1, 'diaria', '{"vezes_por_dia":1,"janelas":["08:00"]}');

insert into checklist_item (empresa_id, versao_id, ordem, texto, tipo_resposta) values
  ('22222222-2222-2222-2222-222222222222', 'b2410000-0000-0000-0000-000000000001', 1,
   'Lavagem de mãos à entrada', 'booleano');

update checklist_template_versao
   set estado = 'publicada', publicada_em = now()
 where id = 'b2410000-0000-0000-0000-000000000001';
