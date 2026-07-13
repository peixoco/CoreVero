-- =====================================================================
-- 11_biblioteca_base_test.sql — R2a: instalar_templates_base()
-- Pré: bootstrap + migrações + seed.
--
-- Cobre a Tarefa 4.4 do prompt R2a:
--   T1  instala os 7 templates em rascunho (empresa nova, sem templates);
--       nenhum publicado; itens com proveniência; óleo ligado a limite_legal;
--   T2  segunda chamada não duplica (idempotente, retorno explícito);
--   T3  empresa que JÁ tem templates (seed da empresa A) não recebe nada;
--   T4  kiosk não instala (RPC exige admin).
--
-- Tudo dentro de uma transação; rollback no fim.
-- =====================================================================
\set ON_ERROR_STOP on
begin;

-- empresa C: tenant limpo só para este teste
insert into empresa (id, nome, plano, lojas_licenciadas, colaboradores_licenciados) values
  ('33333333-3333-3333-3333-333333333333', 'Tenant Biblioteca (teste)', 'teste', 1, 5);

\set ADMIN_C '{"sub":"0c000000-0000-0000-0000-0000000000cc","app_metadata":{"empresa_id":"33333333-3333-3333-3333-333333333333","tipo":"admin","loja_id":null}}'
\set ADMIN_A '{"sub":"0a000000-0000-0000-0000-0000000000aa","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'
\set KIOSK_C '{"sub":"0k000000-0000-0000-0000-0000000000cc","app_metadata":{"empresa_id":"33333333-3333-3333-3333-333333333333","tipo":"kiosk","loja_id":null}}'

-- =====================================================================
-- T1 + T2 — instalação e idempotência (como admin C)
-- =====================================================================
set request.jwt.claims = :'ADMIN_C';
set role authenticated;
do $$
declare
  v_res json;
begin
  -- T1: instala os 7
  v_res := public.instalar_templates_base();
  if (v_res ->> 'instalados')::int <> 7 then
    raise exception 'FALHA T1: esperado instalados=7, obtido %', v_res::text;
  end if;

  if (select count(*) from checklist_template) <> 7 then
    raise exception 'FALHA T1: esperados 7 templates, obtidos %',
      (select count(*) from checklist_template);
  end if;
  if (select count(*) from checklist_template_versao where estado = 'rascunho') <> 7 then
    raise exception 'FALHA T1: esperadas 7 versões em rascunho';
  end if;
  if exists (select 1 from checklist_template_versao
              where estado <> 'rascunho'
                and empresa_id = '33333333-3333-3333-3333-333333333333') then
    raise exception 'FALHA T1: a biblioteca base publicou uma versão — proibido';
  end if;

  -- todos os itens têm proveniência preenchida
  if exists (select 1 from checklist_item i
              join checklist_template_versao v on v.id = i.versao_id
             where v.empresa_id = '33333333-3333-3333-3333-333333333333'
               and (i.limite_fonte is null or i.limite_referencia is null)) then
    raise exception 'FALHA T1: item da biblioteca sem proveniência (limite_fonte/limite_referencia)';
  end if;

  -- os 2 itens do óleo estão ligados a limite_legal (lei)
  if (select count(*) from checklist_item i
       where i.empresa_id = '33333333-3333-3333-3333-333333333333'
         and i.limite_legal_id is not null and i.limite_fonte = 'lei') <> 2 then
    raise exception 'FALHA T1: esperados 2 itens ligados a limite_legal (óleo de fritura)';
  end if;

  raise notice 'TESTE 1 (7 templates em rascunho, proveniência, óleo ligado à lei): OK';

  -- T2: segunda chamada não duplica
  v_res := public.instalar_templates_base();
  if (v_res ->> 'instalados')::int <> 0 then
    raise exception 'FALHA T2: segunda chamada devia instalar 0, obtido %', v_res::text;
  end if;
  if (select count(*) from checklist_template) <> 7 then
    raise exception 'FALHA T2: segunda chamada duplicou templates';
  end if;
  raise notice 'TESTE 2 (idempotência: segunda chamada não duplica): OK';
end $$;
reset role;

-- =====================================================================
-- T3 — empresa A (já tem o template do seed) não recebe a biblioteca
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
declare
  v_res   json;
  v_antes int;
begin
  select count(*) into v_antes from checklist_template;
  v_res := public.instalar_templates_base();
  if (v_res ->> 'instalados')::int <> 0 then
    raise exception 'FALHA T3: empresa com templates devia receber 0, obtido %', v_res::text;
  end if;
  if (select count(*) from checklist_template) <> v_antes then
    raise exception 'FALHA T3: contagem de templates da empresa A mudou';
  end if;
  raise notice 'TESTE 3 (empresa com templates existentes: no-op): OK';
end $$;
reset role;

-- =====================================================================
-- T4 — kiosk não instala
-- =====================================================================
set request.jwt.claims = :'KIOSK_C';
set role authenticated;
do $$
declare v_res json;
begin
  begin
    v_res := public.instalar_templates_base();
    raise exception 'FALHA T4: kiosk conseguiu instalar a biblioteca';
  exception when insufficient_privilege then null;
  end;
  raise notice 'TESTE 4 (kiosk não instala): OK';
end $$;
reset role;

rollback;
select 'BIBLIOTECA BASE: TODOS OS TESTES PASSARAM' as resultado;
