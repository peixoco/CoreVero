-- =====================================================================
-- 10_checklist_versionamento_test.sql — R2a: schema checklist_* (doc 13)
-- Pré: bootstrap + migrações + seed (versão publicada a1410000-…001 de A).
--
-- Cobre a Tarefa 4 do prompt R2a:
--   T1  imutabilidade: UPDATE/DELETE de versão publicada e dos seus itens
--       rejeitados (e INSERT de item em versão publicada também);
--   T2  grants de coluna: cliente admin não muda "estado" diretamente;
--       limite_legal é legível mas não escrevível por clientes;
--   T3  publicar_versao: sem itens → falha; limite menos exigente que o
--       estatutário → falha com relatório; corrigido → publica; publicar
--       versão nova arquiva a anterior; validação de frequencia_config;
--   T4  rascunho único: segundo rascunho rejeitado (RPC e INSERT direto);
--   T5  kiosk não publica (RPC exige admin).
--   (instalar_templates_base: NÃO testada — RPC não implementada por
--    ausência do doc 04 no repo; divergência em docs/R2a-notas.md.)
--
-- Tudo dentro de uma transação; rollback no fim (não muta o estado).
-- =====================================================================
\set ON_ERROR_STOP on
begin;

\set A '11111111-1111-1111-1111-111111111111'
\set ADMIN_A '{"sub":"0a000000-0000-0000-0000-0000000000aa","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'
\set KIOSK_CC '{"sub":"0k000000-0000-0000-0000-0000000000kk","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'

-- =====================================================================
-- T1 — imutabilidade da versão publicada e dos seus itens (como
-- superuser: prova que é o TRIGGER a travar, não RLS nem grants)
-- =====================================================================
do $$
begin
  -- UPDATE de versão publicada
  begin
    update checklist_template_versao
       set frequencia_tipo = 'semanal'
     where id = 'a1410000-0000-0000-0000-000000000001';
    raise exception 'FALHA T1: versão publicada aceitou UPDATE';
  exception when raise_exception then
    if sqlerrm like 'FALHA T1%' then raise; end if;
  end;

  -- DELETE de versão publicada
  begin
    delete from checklist_template_versao
     where id = 'a1410000-0000-0000-0000-000000000001';
    raise exception 'FALHA T1: versão publicada aceitou DELETE';
  exception when raise_exception then
    if sqlerrm like 'FALHA T1%' then raise; end if;
  end;

  -- UPDATE de item de versão publicada
  begin
    update checklist_item set texto = 'adulterado'
     where versao_id = 'a1410000-0000-0000-0000-000000000001' and ordem = 1;
    raise exception 'FALHA T1: item de versão publicada aceitou UPDATE';
  exception when raise_exception then
    if sqlerrm like 'FALHA T1%' then raise; end if;
  end;

  -- DELETE de item de versão publicada
  begin
    delete from checklist_item
     where versao_id = 'a1410000-0000-0000-0000-000000000001' and ordem = 1;
    raise exception 'FALHA T1: item de versão publicada aceitou DELETE';
  exception when raise_exception then
    if sqlerrm like 'FALHA T1%' then raise; end if;
  end;

  -- INSERT de item em versão publicada (publicar congela — D1)
  begin
    insert into checklist_item (empresa_id, versao_id, ordem, texto, tipo_resposta)
    values ('11111111-1111-1111-1111-111111111111',
            'a1410000-0000-0000-0000-000000000001', 99, 'item intruso', 'texto');
    raise exception 'FALHA T1: versão publicada aceitou item novo';
  exception when raise_exception then
    if sqlerrm like 'FALHA T1%' then raise; end if;
  end;

  raise notice 'TESTE 1 (versão publicada e itens imutáveis): OK';
end $$;

-- =====================================================================
-- T2 — grants: cliente não toca no estado; limite_legal só-leitura
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  -- publicar "à mão" (UPDATE direto do estado) → barrado por grant de coluna
  begin
    update checklist_template_versao set estado = 'arquivada'
     where id = 'a1410000-0000-0000-0000-000000000001';
    raise exception 'FALHA T2: cliente alterou o estado da versão diretamente';
  exception when insufficient_privilege then null;
  end;

  -- limite_legal: leitura global OK, escrita barrada
  if (select count(*) from limite_legal) <> 2 then
    raise exception 'FALHA T2: admin devia ler 2 limites legais';
  end if;
  begin
    insert into limite_legal (controlo, descricao, norma, unidade, limite_max)
    values ('injetado', 'x', 'y', 'z', 1);
    raise exception 'FALHA T2: cliente escreveu em limite_legal';
  exception when insufficient_privilege then null;
  end;

  raise notice 'TESTE 2 (estado só via RPC; limite_legal só-leitura): OK';
end $$;

-- =====================================================================
-- T3 — publicar_versao: validações + publicação + arquivo da anterior
-- (continua como ADMIN_A / authenticated)
-- =====================================================================
do $$
declare
  v_template uuid;
  v_versao   uuid;
  v_item     uuid;
  v_legal    uuid;
  v_res      json;
begin
  select id into v_legal from limite_legal where controlo = 'oleo_fritura_temperatura';

  insert into checklist_template (empresa_id, nome)
  values ('11111111-1111-1111-1111-111111111111', 'Óleo de fritura (teste)')
  returning id into v_template;

  insert into checklist_template_versao (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
  values ('11111111-1111-1111-1111-111111111111', v_template, 1, 'por_evento', '{}')
  returning id into v_versao;

  -- (a) sem itens → falha com erro claro
  begin
    v_res := public.publicar_versao(v_versao);
    raise exception 'FALHA T3a: publicou versão sem itens';
  exception when raise_exception then
    if sqlerrm like 'FALHA T3a%' then raise; end if;
    if sqlerrm not like '%não tem itens%' then
      raise exception 'FALHA T3a: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- (b) item ligado a limite_legal com limite MENOS exigente (200 > 180) → falha
  insert into checklist_item (empresa_id, versao_id, ordem, texto, tipo_resposta,
                              unidade, limite_max, limite_fonte, limite_referencia, limite_legal_id)
  values ('11111111-1111-1111-1111-111111111111', v_versao, 1, 'Temperatura do óleo',
          'numerico', '°C', 200, 'lei', 'Portaria 1135/95', v_legal)
  returning id into v_item;

  begin
    v_res := public.publicar_versao(v_versao);
    raise exception 'FALHA T3b: publicou limite menos exigente que o estatutário';
  exception when raise_exception then
    if sqlerrm like 'FALHA T3b%' then raise; end if;
    if sqlerrm not like '%menos exigente%' then
      raise exception 'FALHA T3b: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- (c) frequencia_config incoerente também entra no relatório
  update checklist_template_versao
     set frequencia_tipo = 'diaria', frequencia_config = '{"vezes_por_dia":2,"janelas":["08:00"]}'
   where id = v_versao;
  begin
    v_res := public.publicar_versao(v_versao);
    raise exception 'FALHA T3c: publicou com janelas incoerentes';
  exception when raise_exception then
    if sqlerrm like 'FALHA T3c%' then raise; end if;
    if sqlerrm not like '%janelas%' then
      raise exception 'FALHA T3c: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- (d) corrigido (175 ≤ 180, config coerente) → publica
  update checklist_item set limite_max = 175 where id = v_item;
  update checklist_template_versao
     set frequencia_config = '{"vezes_por_dia":2,"janelas":["08:00","16:00"]}'
   where id = v_versao;
  v_res := public.publicar_versao(v_versao);

  if (select estado from checklist_template_versao where id = v_versao) <> 'publicada' then
    raise exception 'FALHA T3d: versão não ficou publicada';
  end if;
  if (select publicada_em from checklist_template_versao where id = v_versao) is null then
    raise exception 'FALHA T3d: publicada_em não foi preenchido';
  end if;

  -- (e) criar rascunho a partir da publicada, publicar → anterior arquivada
  v_res := public.criar_rascunho_de(v_versao);
  if (v_res ->> 'numero')::int <> 2 or (v_res ->> 'itens_clonados')::int <> 1 then
    raise exception 'FALHA T3e: rascunho clonado inesperado: %', v_res::text;
  end if;

  v_res := public.publicar_versao((v_res ->> 'versao_id')::uuid);
  if (select estado from checklist_template_versao where id = v_versao) <> 'arquivada' then
    raise exception 'FALHA T3e: versão anterior não foi arquivada';
  end if;
  if (v_res ->> 'versao_arquivada')::int <> 1 then
    raise exception 'FALHA T3e: RPC não reportou a versão arquivada';
  end if;

  raise notice 'TESTE 3 (publicar_versao: validações, publicação, arquivo): OK';
end $$;

-- =====================================================================
-- T4 — um rascunho por template: RPC falha limpo; INSERT direto viola
-- constraint (continua como ADMIN_A / authenticated)
-- =====================================================================
do $$
declare
  v_versao2 uuid;
  v_res     json;
begin
  -- template do T3: a versão 2 está publicada; criar rascunho (v3) OK
  select id into v_versao2 from checklist_template_versao
   where numero = 2 and estado = 'publicada'
     and template_id = (select id from checklist_template where nome = 'Óleo de fritura (teste)');

  v_res := public.criar_rascunho_de(v_versao2);

  -- segundo rascunho via RPC → falha limpa
  begin
    v_res := public.criar_rascunho_de(v_versao2);
    raise exception 'FALHA T4: criou segundo rascunho do mesmo template';
  exception when raise_exception then
    if sqlerrm like 'FALHA T4%' then raise; end if;
    if sqlerrm not like '%já existe um rascunho%' then
      raise exception 'FALHA T4: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- segundo rascunho via INSERT direto → índice único parcial
  begin
    insert into checklist_template_versao (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values ('11111111-1111-1111-1111-111111111111',
            (select id from checklist_template where nome = 'Óleo de fritura (teste)'),
            99, 'por_evento', '{}');
    raise exception 'FALHA T4: INSERT direto de segundo rascunho passou';
  exception when unique_violation then null;
  end;

  raise notice 'TESTE 4 (um rascunho por template): OK';
end $$;
reset role;

-- =====================================================================
-- T5 — kiosk não publica (RPC exige admin)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_res json;
begin
  begin
    v_res := public.publicar_versao('a1410000-0000-0000-0000-000000000001');
    raise exception 'FALHA T5: kiosk conseguiu chamar publicar_versao';
  exception when insufficient_privilege then null;
  end;
  raise notice 'TESTE 5 (kiosk não publica): OK';
end $$;
reset role;

rollback;
select 'CHECKLIST VERSIONAMENTO: TODOS OS TESTES PASSARAM' as resultado;
