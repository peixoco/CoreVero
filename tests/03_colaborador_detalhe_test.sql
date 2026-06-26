-- =====================================================================
-- 03_colaborador_detalhe_test.sql — Sprint 2.
-- Pré: bootstrap + 0001 + 0002 + sprint1 + sprint2 + seed.
-- Prova: detalhe de RH é SÓ admin; kiosk não o lê; pin = 4 dígitos.
-- =====================================================================
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('0a000000-0000-0000-0000-0000000000aa', 'admin@a.pt') on conflict do nothing;
insert into utilizador_app (id, empresa_id, ambito, loja_id) values
  ('0a000000-0000-0000-0000-0000000000aa', '11111111-1111-1111-1111-111111111111', 'empresa', null)
  on conflict do nothing;

\set ADMIN_A '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'
\set KIOSK_CC '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'

-- =====================================================================
-- TESTE 1 — admin cria/lê detalhe de RH; pin válido aceite
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  -- atribuir pin de 4 dígitos a um colaborador existente
  update trabalhador set pin = '4071', area = 'cozinha'
    where id = 'a1200000-0000-0000-0000-000000000001';

  -- inserir o detalhe de RH
  insert into trabalhador_detalhe
    (trabalhador_id, empresa_id, nome_completo, data_nascimento, posicao, telefone, email)
  values
    ('a1200000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
     'Ana Sousa Pereira', '1990-03-14', 'Chefe de partida', '+351912345678', 'ana@exemplo.pt');

  if (select count(*) from trabalhador_detalhe) <> 1 then raise exception 'admin devia ver 1 detalhe'; end if;
  if (select pin from trabalhador where id='a1200000-0000-0000-0000-000000000001') <> '4071'
    then raise exception 'pin não gravou'; end if;
  raise notice 'TESTE 1 (admin cria/lê detalhe + pin): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 2 — kiosk NÃO lê dados de RH, mas LÊ pin/area (fatia fina)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  if (select count(*) from trabalhador_detalhe) <> 0
    then raise exception 'FUGA: kiosk leu dados de RH'; end if;

  -- o kiosk LÊ trabalhador (nome/pin/area) para validar a picagem
  if (select pin from trabalhador where id='a1200000-0000-0000-0000-000000000001') <> '4071'
    then raise exception 'kiosk devia ler o pin do trabalhador'; end if;
  if (select area from trabalhador where id='a1200000-0000-0000-0000-000000000001') <> 'cozinha'
    then raise exception 'kiosk devia ler a area'; end if;

  raise notice 'TESTE 2 (kiosk não lê RH, lê pin/area): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 3 — pin tem de ter 4 dígitos (CHECK)
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  begin
    update trabalhador set pin = '12' where id = 'a1200000-0000-0000-0000-000000000002';
    raise exception 'FALHA: aceitou pin de 2 dígitos';
  exception when check_violation then null; end;

  begin
    update trabalhador set pin = 'abcd' where id = 'a1200000-0000-0000-0000-000000000002';
    raise exception 'FALHA: aceitou pin não-numérico';
  exception when check_violation then null; end;

  raise notice 'TESTE 3 (pin = 4 dígitos forçado): OK';
end $$;
reset role;

select 'SPRINT 2 (colaborador/detalhe): TODOS OS TESTES PASSARAM' as resultado;
