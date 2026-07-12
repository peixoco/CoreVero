-- =====================================================================
-- 04_criar_colaborador_test.sql
-- Pré: bootstrap + 0001 + 0002 + sprint1 + sprint2(detalhe) + intervalos
--      + criar_colaborador + seed.
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
-- TESTE 1 — picagem aceita intervalos; rejeita tipo inválido
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  -- inserir picagens de intervalo (via admin, com uma verificacao existente do seed)
  insert into picagem (empresa_id, verificacao_id, tipo)
    values ('11111111-1111-1111-1111-111111111111','a1300000-0000-0000-0000-000000000001','inicio_intervalo');
  insert into picagem (empresa_id, verificacao_id, tipo)
    values ('11111111-1111-1111-1111-111111111111','a1300000-0000-0000-0000-000000000001','fim_intervalo');

  begin
    insert into picagem (empresa_id, verificacao_id, tipo)
      values ('11111111-1111-1111-1111-111111111111','a1300000-0000-0000-0000-000000000001','almoco');
    raise exception 'FALHA: aceitou tipo de picagem inválido';
  exception when check_violation then null; end;

  raise notice 'TESTE 1 (picagem aceita intervalos, rejeita inválido): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 2 — admin cria colaborador (atómico): trabalhador + detalhe + pin
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
declare r record;
begin
  select * into r from public.criar_colaborador(
    p_nome := 'Carla', p_area := 'sala',
    p_nome_completo := 'Carla Mendes', p_posicao := 'Empregada de mesa',
    p_contrato_inicio := '2026-01-15', p_telefone := '+351911111111'
  );

  if r.pin !~ '^[0-9]{4}$' then raise exception 'pin não é 4 dígitos: %', r.pin; end if;
  if r.codigo_pessoal is null then raise exception 'codigo_pessoal vazio'; end if;

  -- ambas as camadas criadas, mesma id
  if not exists (select 1 from public.trabalhador where id = r.trabalhador_id and nome='Carla' and area='sala')
    then raise exception 'trabalhador não criado'; end if;
  if not exists (select 1 from public.trabalhador_detalhe where trabalhador_id = r.trabalhador_id and nome_completo='Carla Mendes')
    then raise exception 'detalhe não criado'; end if;

  raise notice 'TESTE 2 (criar_colaborador atómico + pin %): OK', r.pin;
end $$;
reset role;

-- =====================================================================
-- TESTE 3 — kiosk NÃO pode criar colaborador (não é admin)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.criar_colaborador(p_nome := 'Hacker', p_area := 'cozinha');
    raise exception 'FALHA: kiosk criou colaborador';
  exception when insufficient_privilege then null; end;
  raise notice 'TESTE 3 (kiosk não cria colaborador): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 4 — gerar_novo_pin (admin) muda o pin
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
declare v_novo text;
begin
  v_novo := public.gerar_novo_pin('a1200000-0000-0000-0000-000000000001');
  if v_novo !~ '^[0-9]{4}$' then raise exception 'novo pin inválido'; end if;
  -- a leitura do pin está revogada aos clientes; verificar como superuser
  reset role;
  if (select pin from public.trabalhador where id='a1200000-0000-0000-0000-000000000001') <> v_novo
    then raise exception 'pin não atualizou'; end if;
  raise notice 'TESTE 4 (gerar_novo_pin: %): OK', v_novo;
end $$;
reset role;

select 'COLABORADOR/PICAGEM: TODOS OS TESTES PASSARAM' as resultado;
