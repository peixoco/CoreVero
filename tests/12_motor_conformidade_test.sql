-- =====================================================================
-- 12_motor_conformidade_test.sql — R2b: motor de conformidade e RPC
-- de preenchimento (Tarefa 5).
--
-- Cobre: avaliar_conformidade (pura, superuser direto), registar_checklist
-- (kiosk authenticated), imutabilidade pós-fecho (triggers),
-- obter_checklists_kiosk.
-- Tudo dentro de uma transação; rollback no fim (não muta o estado).
--
-- UUIDs prefixo c04*: template/versão/item criados neste teste.
-- UUIDs prefixo cc12*: kiosks criados neste teste.
-- =====================================================================
\set ON_ERROR_STOP on
begin;

-- =====================================================================
-- SETUP (superuser) — empresa/lojas existem no seed; criamos aqui:
-- PIN para Ana, kiosks, template com versão publicada e rascunho,
-- template de loja específica para o teste B2-7.
-- =====================================================================

-- PIN de Ana Sousa (trabalhador a12000...001, codigo_pessoal='1001')
update trabalhador set pin = '9999'
  where id = 'a1200000-0000-0000-0000-000000000001';

-- auth.users + kiosks (loja A1 = Cozinha Central, loja A2 = Esplanada)
insert into auth.users (id, email) values
  ('cc120000-0000-0000-0000-000000000001', 'kiosk-12-a1@teste.local'),
  ('cc120000-0000-0000-0000-000000000002', 'kiosk-12-a2@teste.local')
on conflict (id) do nothing;

insert into public.kiosk (id, empresa_id, loja_id, ativo) values
  ('cc120000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'a1100000-0000-0000-0000-000000000001', true),
  ('cc120000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'a1100000-0000-0000-0000-000000000002', true)
on conflict (id) do nothing;

-- Template empresa-wide (loja_id null) — versão publicada com itens variados
insert into checklist_template
  (id, empresa_id, loja_id, nome, ativo)
values
  ('c0400000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   null, 'Motor de conformidade (teste)', true);

-- Versão nasce rascunho; itens são inseridos; depois marcada publicada
insert into checklist_template_versao
  (id, empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
values
  ('c0410000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'c0400000-0000-0000-0000-000000000001',
   1, 'por_evento', '{}');

-- 7 itens (ordem 1..7):
--  1: numérico com limite_min e limite_max (0..5 °C)
--  2: numérico só com limite_max (null..-18 °C)
--  3: booleano com booleano_conforme = false (pragas)
--  4: booleano normal (booleano_conforme = true)
--  5: texto obrigatório
--  6: foto (obrigatório)
--  7: texto não obrigatório
insert into checklist_item
  (id, empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
   limite_min, limite_max, booleano_conforme, obrigatorio)
values
  ('c0420000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   1, 'Temperatura frigorifico (0..5°C)', 'numerico', '°C', 0, 5, null, true),
  ('c0420000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   2, 'Temperatura congelador (max -18°C)', 'numerico', '°C', null, -18, null, true),
  ('c0420000-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   3, 'Sinais de pragas observados', 'booleano', null, null, null, false, true),
  ('c0420000-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   4, 'Luvas utilizadas', 'booleano', null, null, null, true, true),
  ('c0420000-0000-0000-0000-000000000005',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   5, 'Observações gerais', 'texto', null, null, null, null, true),
  ('c0420000-0000-0000-0000-000000000006',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   6, 'Foto da câmara fria', 'foto', null, null, null, null, true),
  ('c0420000-0000-0000-0000-000000000007',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000001',
   7, 'Observações extras (opcional)', 'texto', null, null, null, null, false);

-- Marcar versão como publicada (superuser contorna o grant de coluna;
-- o trigger de imutabilidade só bloqueia UPDATE de versões já publicadas/arquivadas)
update checklist_template_versao
   set estado = 'publicada', publicada_em = now()
 where id = 'c0410000-0000-0000-0000-000000000001';

-- Versão em rascunho do mesmo template (para teste B2-6)
insert into checklist_template_versao
  (id, empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
values
  ('c0410000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'c0400000-0000-0000-0000-000000000001',
   2, 'por_evento', '{}');

-- Template específico da loja A2 (Esplanada) — para teste B2-7
insert into checklist_template
  (id, empresa_id, loja_id, nome, ativo)
values
  ('c0400000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'a1100000-0000-0000-0000-000000000002',
   'Template da Esplanada (teste)', true);

insert into checklist_template_versao
  (id, empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
values
  ('c0410000-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111',
   'c0400000-0000-0000-0000-000000000002',
   1, 'por_evento', '{}');

insert into checklist_item
  (id, empresa_id, versao_id, ordem, texto, tipo_resposta, obrigatorio)
values
  ('c0420000-0000-0000-0000-000000000008',
   '11111111-1111-1111-1111-111111111111',
   'c0410000-0000-0000-0000-000000000003',
   1, 'Item da Esplanada', 'texto', true);

update checklist_template_versao
   set estado = 'publicada', publicada_em = now()
 where id = 'c0410000-0000-0000-0000-000000000003';

-- Tabela temporária para partilha de IDs entre blocos
create temp table _bloco3_ids (
  instancia_id uuid,
  resposta_nc_id uuid,
  acao_id uuid
);

-- =====================================================================
-- BLOCO 1 — avaliar_conformidade (chamada direta como superuser)
-- Sem set role: revoke de authenticated não afeta superuser.
-- =====================================================================

-- ---- TESTE 1: numérico com limite_min e limite_max ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000001';

  -- dentro dos limites: conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, '3', null) ac;
  if not v_conf then
    raise exception 'FALHA TESTE 1a: valor 3 dentro de 0..5 deveria ser conforme (motivo: %)', v_motivo;
  end if;

  -- acima do max (6 > 5): não conforme, motivo menciona "acima"
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, '6', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 1b: valor 6 deveria ser não conforme';
  end if;
  if v_motivo not like '%acima%' then
    raise exception 'FALHA TESTE 1b: motivo não menciona "acima": %', v_motivo;
  end if;

  -- abaixo do min (-1 < 0): não conforme, motivo menciona "abaixo"
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, '-1', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 1c: valor -1 deveria ser não conforme';
  end if;
  if v_motivo not like '%abaixo%' then
    raise exception 'FALHA TESTE 1c: motivo não menciona "abaixo": %', v_motivo;
  end if;

  raise notice 'TESTE 1 (numérico dentro/acima/abaixo dos limites): OK';
end $$;

-- ---- TESTE 2: numérico — valor NULL e valor 'abc' → ilegível ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000001';

  -- NULL → ilegível
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, null, null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 2a: NULL deveria ser não conforme';
  end if;
  if v_motivo <> 'valor ilegível' then
    raise exception 'FALHA TESTE 2a: motivo errado: %', v_motivo;
  end if;

  -- 'abc' → ilegível
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, 'abc', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 2b: "abc" deveria ser não conforme';
  end if;
  if v_motivo <> 'valor ilegível' then
    raise exception 'FALHA TESTE 2b: motivo errado: %', v_motivo;
  end if;

  raise notice 'TESTE 2 (numérico NULL/inválido → ilegível): OK';
end $$;

-- ---- TESTE 3: numérico com limite_min null (só limite_max) ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  -- ITEM_NUM_MAX: limite_min=null, limite_max=-18
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000002';

  -- qualquer valor abaixo do max: conforme (sem limite_min)
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, '-20', null) ac;
  if not v_conf then
    raise exception 'FALHA TESTE 3a: -20 com max=-18 e sem min deveria ser conforme (motivo: %)', v_motivo;
  end if;

  -- acima do max (-10 > -18): não conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, '-10', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 3b: -10 deveria ser não conforme (max=-18)';
  end if;
  if v_motivo not like '%acima%' then
    raise exception 'FALHA TESTE 3b: motivo não menciona "acima": %', v_motivo;
  end if;

  raise notice 'TESTE 3 (numérico só com limite_max): OK';
end $$;

-- ---- TESTE 4: booleano com booleano_conforme = false (pragas) ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  -- ITEM_BOOL_PRAGAS: booleano_conforme=false
  -- conforme = (valor = booleano_conforme) = (false = false) = true
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000003';

  -- 'false' → conforme (sem pragas = tudo bem)
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, 'false', null) ac;
  if not v_conf then
    raise exception 'FALHA TESTE 4a: pragas "false" deveria ser conforme (motivo: %)', v_motivo;
  end if;

  -- 'true' → não conforme (pragas observadas)
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, 'true', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 4b: pragas "true" deveria ser não conforme';
  end if;

  raise notice 'TESTE 4 (booleano booleano_conforme=false): OK';
end $$;

-- ---- TESTE 5: booleano default (booleano_conforme = true) ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  -- ITEM_BOOL_NORMAL: booleano_conforme=true
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000004';

  -- 'true' → conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, 'true', null) ac;
  if not v_conf then
    raise exception 'FALHA TESTE 5a: "true" deveria ser conforme (motivo: %)', v_motivo;
  end if;

  -- 'false' → não conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, 'false', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 5b: "false" deveria ser não conforme';
  end if;

  raise notice 'TESTE 5 (booleano default booleano_conforme=true): OK';
end $$;

-- ---- TESTE 6: texto obrigatório ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  -- ITEM_TEXTO_OBR: texto, obrigatorio=true
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000005';

  -- valor vazio → não conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, '', null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 6a: texto vazio em obrigatório deveria ser não conforme';
  end if;

  -- NULL → não conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, null, null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 6b: NULL em texto obrigatório deveria ser não conforme';
  end if;

  -- com texto → conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, 'tudo bem', null) ac;
  if not v_conf then
    raise exception 'FALHA TESTE 6c: texto preenchido deveria ser conforme (motivo: %)', v_motivo;
  end if;

  raise notice 'TESTE 6 (texto obrigatório vazio/NULL/preenchido): OK';
end $$;

-- ---- TESTE 7: foto ----
do $$
declare
  v_item   public.checklist_item;
  v_conf   boolean;
  v_motivo text;
begin
  -- ITEM_FOTO
  select * into v_item from public.checklist_item
   where id = 'c0420000-0000-0000-0000-000000000006';

  -- sem foto_url → não conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, null, null) ac;
  if v_conf then
    raise exception 'FALHA TESTE 7a: sem foto_url deveria ser não conforme';
  end if;

  -- com foto_url → conforme
  select ac.conforme, ac.motivo into v_conf, v_motivo
    from public.avaliar_conformidade(v_item, null, 'http://foto.jpg') ac;
  if not v_conf then
    raise exception 'FALHA TESTE 7b: com foto_url deveria ser conforme (motivo: %)', v_motivo;
  end if;

  raise notice 'TESTE 7 (foto sem/com foto_url): OK';
end $$;

-- =====================================================================
-- BLOCO 2 — registar_checklist (kiosk authenticated)
-- Claims: KIOSK_A1 = loja Cozinha Central
-- =====================================================================

\set KIOSK_A1 '{"sub":"cc120000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'
\set KIOSK_A2 '{"sub":"cc120000-0000-0000-0000-000000000002","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000002"}}'
\set ADMIN_A  '{"sub":"ad120000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'

-- ---- TESTE 8: caminho feliz — todas as respostas conformes ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_res         json;
  v_inst_id     uuid;
  v_vid         uuid;
  v_momento     timestamptz := now() - interval '3 minutes';
  v_foto_path   text;
  v_esperado    text;
begin
  v_res := public.registar_checklist(
    '1001', '9999',
    'c0410000-0000-0000-0000-000000000001'::uuid,
    v_momento,
    jsonb_build_array(
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000001', 'valor', '3'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000002', 'valor', '-20'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000003', 'valor', 'false'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000004', 'valor', 'true'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000005', 'valor', 'tudo conforme'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000006', 'foto_url', 'http://foto-item.jpg'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000007', 'valor', 'extra')
    ),
    '[]'::jsonb
  );

  -- resumo deve ter campos esperados
  v_inst_id := (v_res->>'instancia_id')::uuid;
  v_vid     := (v_res->>'verificacao_id')::uuid;
  v_foto_path := v_res->>'foto_path';
  if v_inst_id is null then raise exception 'FALHA TESTE 8: instancia_id em falta no resumo'; end if;
  if v_vid     is null then raise exception 'FALHA TESTE 8: verificacao_id em falta no resumo'; end if;
  if (v_res->>'respostas')::int <> 7 then
    raise exception 'FALHA TESTE 8: esperadas 7 respostas, obtidas %', v_res->>'respostas';
  end if;
  if (v_res->>'nao_conformes')::int <> 0 then
    raise exception 'FALHA TESTE 8: não deveria haver não conformes';
  end if;

  reset role;

  -- verificar instância: estado='concluida', concluida_em not null, versao_id correto
  if (select estado from checklist_instancia where id = v_inst_id) <> 'concluida' then
    raise exception 'FALHA TESTE 8: instância não está concluída';
  end if;
  if (select concluida_em from checklist_instancia where id = v_inst_id) is null then
    raise exception 'FALHA TESTE 8: concluida_em é null';
  end if;
  if (select versao_id from checklist_instancia where id = v_inst_id)
     <> 'c0410000-0000-0000-0000-000000000001'::uuid then
    raise exception 'FALHA TESTE 8: versao_id errado na instância';
  end if;

  -- verificar verificacao: momento_dispositivo e foto_url com caminho correto
  if abs(extract(epoch from
      (select momento_dispositivo from verificacao where id = v_vid) - v_momento
    )) > 1 then
    raise exception 'FALHA TESTE 8: momento_dispositivo diverge do enviado';
  end if;
  v_esperado := '11111111-1111-1111-1111-111111111111'
                || '/a1100000-0000-0000-0000-000000000001'
                || '/a1200000-0000-0000-0000-000000000001/'
                || v_vid::text || '.jpg';
  if (select foto_url from verificacao where id = v_vid) <> v_esperado then
    raise exception 'FALHA TESTE 8: foto_url na verificacao errado (esperado: %, obtido: %)',
      v_esperado, (select foto_url from verificacao where id = v_vid);
  end if;
  if v_foto_path <> v_esperado then
    raise exception 'FALHA TESTE 8: foto_path no resumo não coincide com foto_url';
  end if;

  -- todas as respostas conformes
  if exists (
    select 1 from checklist_resposta
     where instancia_id = v_inst_id and not conforme
  ) then
    raise exception 'FALHA TESTE 8: existem respostas não conformes no caminho feliz';
  end if;

  -- zero notificações associadas a estas respostas
  if exists (
    select 1 from notificacao n
     join checklist_resposta r on r.id = n.origem_id
    where r.instancia_id = v_inst_id
  ) then
    raise exception 'FALHA TESTE 8: não deveria haver notificações no caminho feliz';
  end if;

  raise notice 'TESTE 8 (caminho feliz — tudo conforme): OK';
end $$;
reset role;

-- ---- TESTE 9: não conforme COM ação → sucesso + notificação ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_res       json;
  v_inst_id   uuid;
  v_resp_nc   uuid;
begin
  v_res := public.registar_checklist(
    '1001', '9999',
    'c0410000-0000-0000-0000-000000000001'::uuid,
    now() - interval '2 minutes',
    jsonb_build_array(
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000001', 'valor', '9'),  -- nc: 9 > 5
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000002', 'valor', '-20'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000003', 'valor', 'false'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000004', 'valor', 'true'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000005', 'valor', 'ajustei a temperatura'),
      jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000006', 'foto_url', 'http://foto2.jpg')
    ),
    jsonb_build_array(
      jsonb_build_object(
        'item_id', 'c0420000-0000-0000-0000-000000000001',
        'descricao', 'Ajustei o termostato imediatamente'
      )
    )
  );

  v_inst_id := (v_res->>'instancia_id')::uuid;
  if (v_res->>'nao_conformes')::int <> 1 then
    raise exception 'FALHA TESTE 9: esperado 1 não conforme, obtido %', v_res->>'nao_conformes';
  end if;
  if (v_res->>'acoes')::int <> 1 then
    raise exception 'FALHA TESTE 9: esperada 1 ação, obtida %', v_res->>'acoes';
  end if;

  reset role;

  -- resposta do item numérico nc: conforme=false
  select id into v_resp_nc
    from checklist_resposta
   where instancia_id = v_inst_id
     and item_id = 'c0420000-0000-0000-0000-000000000001'::uuid;
  if v_resp_nc is null then
    raise exception 'FALHA TESTE 9: resposta não encontrada';
  end if;
  if (select conforme from checklist_resposta where id = v_resp_nc) then
    raise exception 'FALHA TESTE 9: resposta deveria estar marcada como não conforme';
  end if;

  -- acao_corretiva ligada à resposta e à verificacao
  if not exists (
    select 1 from acao_corretiva
     where resposta_id    = v_resp_nc
       and verificacao_id = (select verificacao_id from checklist_instancia where id = v_inst_id)
  ) then
    raise exception 'FALHA TESTE 9: acao_corretiva não criada ou ligação incorreta';
  end if;

  -- notificacao criada: canal='email', estado='pendente', origem_id=resposta nc
  if not exists (
    select 1 from notificacao
     where origem_id = v_resp_nc
       and canal = 'email'
       and estado = 'pendente'
  ) then
    raise exception 'FALHA TESTE 9: notificacao não criada ou campos errados';
  end if;

  -- guardar ids para Bloco 3
  insert into _bloco3_ids (instancia_id, resposta_nc_id, acao_id)
  select v_inst_id, v_resp_nc,
    (select id from acao_corretiva where resposta_id = v_resp_nc limit 1);

  raise notice 'TESTE 9 (não conforme COM ação): OK';
end $$;
reset role;

-- ---- TESTE 10: não conforme SEM ação → exceção; nada persistido ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_n_antes  bigint;
  v_n_depois bigint;
  v_exc      text := '';
begin
  reset role;
  select count(*) into v_n_antes from checklist_instancia
   where empresa_id = '11111111-1111-1111-1111-111111111111';
  set role authenticated;

  begin
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000001'::uuid,
      now(),
      jsonb_build_array(
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000001', 'valor', '99'),  -- nc
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000002', 'valor', '-20'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000003', 'valor', 'false'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000004', 'valor', 'true'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000005', 'valor', 'ok'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000006', 'foto_url', 'http://f.jpg')
      ),
      '[]'::jsonb  -- sem ação para o item nc
    );
    raise exception 'FALHA TESTE 10: deveria ter rejeitado (sem ação para não conforme)';
  exception when raise_exception then
    v_exc := sqlerrm;
    if v_exc like 'FALHA TESTE 10%' then raise; end if;
    -- verificar que menciona o item
    if v_exc not like '%Temperatura frigorifico%' then
      raise exception 'FALHA TESTE 10: exceção não menciona o item nc: %', v_exc;
    end if;
  end;

  -- nada persistido
  reset role;
  select count(*) into v_n_depois from checklist_instancia
   where empresa_id = '11111111-1111-1111-1111-111111111111';
  if v_n_depois <> v_n_antes then
    raise exception 'FALHA TESTE 10: instâncias persistiram após falha (antes=%, depois=%)',
      v_n_antes, v_n_depois;
  end if;

  raise notice 'TESTE 10 (não conforme SEM ação — exceção, nada persistido): OK';
end $$;
reset role;

-- ---- TESTE 11: conforme forjado no payload — rejeitado na mesma ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_exc text := '';
begin
  begin
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000001'::uuid,
      now(),
      jsonb_build_array(
        -- conforme:true forjado pelo cliente; valor 100 viola limite_max=5
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000001',
                           'valor', '100', 'conforme', true),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000002', 'valor', '-20'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000003', 'valor', 'false'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000004', 'valor', 'true'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000005', 'valor', 'ok'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000006', 'foto_url', 'http://f.jpg')
      ),
      '[]'::jsonb
    );
    raise exception 'FALHA TESTE 11: conforme forjado foi aceite sem ação';
  exception when raise_exception then
    v_exc := sqlerrm;
    if v_exc like 'FALHA TESTE 11%' then raise; end if;
    if v_exc not like '%requer uma ação corretiva%' then
      raise exception 'FALHA TESTE 11: mensagem inesperada: %', v_exc;
    end if;
  end;
  raise notice 'TESTE 11 (conforme forjado rejeitado — servidor reavalia): OK';
end $$;
reset role;

-- ---- TESTE 12: item obrigatório sem resposta → exceção com relatório ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_exc text := '';
begin
  begin
    -- omite ITEM_TEXTO_OBR e ITEM_FOTO (ambos obrigatórios)
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000001'::uuid,
      now(),
      jsonb_build_array(
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000001', 'valor', '3'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000002', 'valor', '-20'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000003', 'valor', 'false'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000004', 'valor', 'true')
        -- sem item_id 5 (texto obrig) nem 6 (foto)
      ),
      '[]'::jsonb
    );
    raise exception 'FALHA TESTE 12: deveria ter rejeitado (obrigatório em falta)';
  exception when raise_exception then
    v_exc := sqlerrm;
    if v_exc like 'FALHA TESTE 12%' then raise; end if;
    if v_exc not like '%Observações gerais%' then
      raise exception 'FALHA TESTE 12: relatório não menciona "Observações gerais": %', v_exc;
    end if;
    if v_exc not like '%Foto da câmara fria%' then
      raise exception 'FALHA TESTE 12: relatório não menciona "Foto da câmara fria": %', v_exc;
    end if;
  end;
  raise notice 'TESTE 12 (item obrigatório em falta → relatório): OK';
end $$;
reset role;

-- ---- TESTE 13: versão em rascunho → rejeitada ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_exc text := '';
begin
  begin
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000002'::uuid,  -- versão RASCUNHO
      now(),
      '[]'::jsonb,
      '[]'::jsonb
    );
    raise exception 'FALHA TESTE 13: versão rascunho foi aceite';
  exception when raise_exception then
    v_exc := sqlerrm;
    if v_exc like 'FALHA TESTE 13%' then raise; end if;
    if v_exc not like '%publicada%' then
      raise exception 'FALHA TESTE 13: mensagem não menciona "publicada": %', v_exc;
    end if;
  end;
  raise notice 'TESTE 13 (versão em rascunho rejeitada): OK';
end $$;
reset role;

-- ---- TESTE 14: kiosk de outra loja (template da loja A2, kiosk da loja A1) ----
-- O kiosk A1 tenta submeter para VERSAO_LOJA2 (template loja_id=A2)
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_exc text := '';
begin
  begin
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000003'::uuid,  -- versão do template da Esplanada (loja A2)
      now(),
      jsonb_build_array(
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000008', 'valor', 'ok')
      ),
      '[]'::jsonb
    );
    raise exception 'FALHA TESTE 14: kiosk de outra loja foi aceite';
  exception when raise_exception then
    v_exc := sqlerrm;
    if v_exc like 'FALHA TESTE 14%' then raise; end if;
    if v_exc not like '%não é aplicável%' then
      raise exception 'FALHA TESTE 14: mensagem inesperada: %', v_exc;
    end if;
  end;
  raise notice 'TESTE 14 (kiosk de loja errada rejeitado): OK';
end $$;
reset role;

-- ---- TESTE 15: PIN errado → mesmo errcode da picagem ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
begin
  begin
    perform public.registar_checklist(
      '1001', '0000',  -- PIN errado
      'c0410000-0000-0000-0000-000000000001'::uuid,
      now(), '[]'::jsonb, '[]'::jsonb
    );
    raise exception 'FALHA TESTE 15: PIN errado foi aceite';
  exception when invalid_authorization_specification then
    null;  -- errcode correto
  end;
  raise notice 'TESTE 15 (PIN errado → invalid_authorization_specification): OK';
end $$;
reset role;

-- ---- TESTE 16: relatório acumulado — dois problemas na mesma exceção ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_exc text := '';
begin
  begin
    -- problema 1: ITEM_TEXTO_OBR ausente (obrigatório em falta)
    -- problema 2: ITEM_NUM_FULL com valor '200' (nc) sem ação
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000001'::uuid,
      now(),
      jsonb_build_array(
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000001', 'valor', '200'),  -- nc, sem acao
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000002', 'valor', '-20'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000003', 'valor', 'false'),
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000004', 'valor', 'true'),
        -- item 5 (texto obrig) ausente
        jsonb_build_object('item_id', 'c0420000-0000-0000-0000-000000000006', 'foto_url', 'http://f.jpg')
      ),
      '[]'::jsonb
    );
    raise exception 'FALHA TESTE 16: deveria ter rejeitado';
  exception when raise_exception then
    v_exc := sqlerrm;
    if v_exc like 'FALHA TESTE 16%' then raise; end if;
    -- deve mencionar ambos os problemas
    if v_exc not like '%Temperatura frigorifico%' then
      raise exception 'FALHA TESTE 16: exceção não menciona item nc: %', v_exc;
    end if;
    if v_exc not like '%Observações gerais%' then
      raise exception 'FALHA TESTE 16: exceção não menciona item obrig em falta: %', v_exc;
    end if;
  end;
  raise notice 'TESTE 16 (relatório acumulado — dois problemas): OK';
end $$;
reset role;

-- ---- TESTE 17: admin não pode chamar registar_checklist ----
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  begin
    perform public.registar_checklist(
      '1001', '9999',
      'c0410000-0000-0000-0000-000000000001'::uuid,
      now(), '[]'::jsonb, '[]'::jsonb
    );
    raise exception 'FALHA TESTE 17: admin conseguiu chamar registar_checklist';
  exception when insufficient_privilege then
    null;  -- correto
  end;
  raise notice 'TESTE 17 (admin não chama registar_checklist): OK';
end $$;
reset role;

-- =====================================================================
-- BLOCO 3 — imutabilidade pós-fecho (como superuser)
-- Usa o instancia_id/resposta_nc_id/acao_id guardados no TESTE 9.
-- =====================================================================
do $$
declare
  v_inst_id  uuid;
  v_resp_id  uuid;
  v_acao_id  uuid;
begin
  select instancia_id, resposta_nc_id, acao_id
    into v_inst_id, v_resp_id, v_acao_id
    from _bloco3_ids;

  if v_inst_id is null then
    raise exception 'FALHA BLOCO 3: _bloco3_ids vazio — TESTE 9 não preencheu?';
  end if;

  -- ---- TESTE 18: UPDATE em checklist_resposta de instância concluída ----
  begin
    update checklist_resposta set conforme = not conforme where id = v_resp_id;
    raise exception 'FALHA TESTE 18: UPDATE de resposta concluída foi aceite';
  exception when raise_exception then
    if sqlerrm like 'FALHA TESTE 18%' then raise; end if;
    if sqlerrm not like '%imutável%' then
      raise exception 'FALHA TESTE 18: mensagem inesperada: %', sqlerrm;
    end if;
  end;
  raise notice 'TESTE 18 (trg_imutavel_resposta_checklist bloqueia UPDATE): OK';

  -- ---- TESTE 19: DELETE em acao_corretiva de instância concluída ----
  begin
    delete from acao_corretiva where id = v_acao_id;
    raise exception 'FALHA TESTE 19: DELETE de acao_corretiva concluída foi aceite';
  exception when raise_exception then
    if sqlerrm like 'FALHA TESTE 19%' then raise; end if;
    if sqlerrm not like '%imutável%' then
      raise exception 'FALHA TESTE 19: mensagem inesperada: %', sqlerrm;
    end if;
  end;
  raise notice 'TESTE 19 (trg_imutavel_acao_corretiva bloqueia DELETE): OK';
end $$;

-- =====================================================================
-- BLOCO 4 — obter_checklists_kiosk
-- =====================================================================

-- ---- TESTE 20: kiosk obtém templates publicados aplicáveis ----
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_res       json;
  v_len       int;
  v_tem_pub   boolean := false;
  v_tem_rasq  boolean := false;
  v_tem_loja2 boolean := false;
  i           int;
  v_elem      json;
begin
  v_res := public.obter_checklists_kiosk();

  -- deve devolver pelo menos os 2 templates publicados da empresa A
  -- (o do seed "Temperaturas de frio" + o nosso "Motor de conformidade")
  -- ambos têm loja_id=null → aplicáveis à loja A1
  v_len := json_array_length(v_res);
  if v_len < 2 then
    raise exception 'FALHA TESTE 20: esperados >= 2 templates, obtidos %', v_len;
  end if;

  -- varrer resultado: verificar que inclui o nosso template publicado
  -- e que NÃO inclui a versão rascunho nem o template da loja A2
  for i in 0..v_len-1 loop
    v_elem := v_res->i;
    if (v_elem->>'versao_id') = 'c0410000-0000-0000-0000-000000000001' then
      v_tem_pub := true;
      -- itens devem estar ordenados por ordem
      if json_array_length(v_elem->'itens') <> 7 then
        raise exception 'FALHA TESTE 20: esperados 7 itens, obtidos %',
          json_array_length(v_elem->'itens');
      end if;
      if ((v_elem->'itens'->0)->>'ordem')::int <> 1 then
        raise exception 'FALHA TESTE 20: itens não começam por ordem=1';
      end if;
    end if;
    if (v_elem->>'versao_id') = 'c0410000-0000-0000-0000-000000000002' then
      v_tem_rasq := true;  -- versão rascunho não deve aparecer
    end if;
    if (v_elem->>'versao_id') = 'c0410000-0000-0000-0000-000000000003' then
      v_tem_loja2 := true;  -- template da loja A2 não deve aparecer para kiosk A1
    end if;
  end loop;

  if not v_tem_pub then
    raise exception 'FALHA TESTE 20: versão publicada do teste não encontrada no resultado';
  end if;
  if v_tem_rasq then
    raise exception 'FALHA TESTE 20: versão rascunho não deveria aparecer';
  end if;
  if v_tem_loja2 then
    raise exception 'FALHA TESTE 20: template da loja A2 não deveria aparecer para kiosk da A1';
  end if;

  raise notice 'TESTE 20 (obter_checklists_kiosk devolve publicados aplicáveis): OK';
end $$;
reset role;

-- ---- TESTE 21: admin não pode chamar obter_checklists_kiosk ----
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  begin
    perform public.obter_checklists_kiosk();
    raise exception 'FALHA TESTE 21: admin conseguiu chamar obter_checklists_kiosk';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'TESTE 21 (admin não chama obter_checklists_kiosk): OK';
end $$;
reset role;

-- ---- TESTE 22: kiosk não lê checklist_template diretamente ----
-- A nova checklist_template (20260713170000) só tem policy admin_empresa.
-- Kiosk tem grant SELECT mas RLS nega (sem policy correspondente) → 0 linhas.
set request.jwt.claims = :'KIOSK_A1';
set role authenticated;
do $$
declare
  v_n bigint;
begin
  select count(*) into v_n from checklist_template;
  if v_n <> 0 then
    raise exception
      'FALHA TESTE 22: kiosk leu % linhas de checklist_template diretamente (RLS deveria devolver 0)', v_n;
  end if;
  raise notice 'TESTE 22 (kiosk sem acesso direto a checklist_template — RLS retorna 0): OK';
end $$;
reset role;

rollback;
select 'MOTOR CONFORMIDADE: TODOS OS TESTES PASSARAM' as resultado;
