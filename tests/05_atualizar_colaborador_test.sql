-- =====================================================================
-- 05_atualizar_colaborador_test.sql
-- =====================================================================
\set ON_ERROR_STOP on
insert into auth.users (id, email) values
  ('0a000000-0000-0000-0000-0000000000aa', 'admin@a.pt') on conflict do nothing;
insert into utilizador_app (id, empresa_id, ambito, loja_id) values
  ('0a000000-0000-0000-0000-0000000000aa', '11111111-1111-1111-1111-111111111111', 'empresa', null)
  on conflict do nothing;
\set ADMIN_A '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'
\set KIOSK_CC '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'

-- Pré-condição do TESTE 1 (Ana sem detalhe): o teste 03 pode tê-lo criado.
delete from trabalhador_detalhe where trabalhador_id = 'a1200000-0000-0000-0000-000000000001';

-- TESTE 1 — editar um colaborador de SEED (sem detalhe) -> upsert cria o detalhe
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  -- Ana (1001) não tem trabalhador_detalhe
  if exists (select 1 from trabalhador_detalhe where trabalhador_id='a1200000-0000-0000-0000-000000000001')
    then raise exception 'pré-condição: Ana não devia ter detalhe ainda'; end if;

  perform public.atualizar_colaborador(
    p_id := 'a1200000-0000-0000-0000-000000000001',
    p_nome := 'Ana S.', p_area := 'cozinha',
    p_nome_completo := 'Ana Sousa', p_data_nascimento := '1992-05-10', p_posicao := 'Cozinheira');

  if (select nome from trabalhador where id='a1200000-0000-0000-0000-000000000001') <> 'Ana S.'
    then raise exception 'nome não atualizou'; end if;
  if (select area from trabalhador where id='a1200000-0000-0000-0000-000000000001') <> 'cozinha'
    then raise exception 'area não atualizou'; end if;
  if (select nome_completo from trabalhador_detalhe where trabalhador_id='a1200000-0000-0000-0000-000000000001') <> 'Ana Sousa'
    then raise exception 'detalhe não foi criado por upsert'; end if;
  raise notice 'TESTE 1 (editar seed worker -> upsert do detalhe): OK';
end $$;
reset role;

-- TESTE 2 — editar de novo (detalhe já existe) -> update
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  perform public.atualizar_colaborador(
    p_id := 'a1200000-0000-0000-0000-000000000001',
    p_nome := 'Ana S.', p_area := 'sala', p_posicao := 'Chefe de sala');
  if (select posicao from trabalhador_detalhe where trabalhador_id='a1200000-0000-0000-0000-000000000001') <> 'Chefe de sala'
    then raise exception 'update do detalhe falhou'; end if;
  raise notice 'TESTE 2 (editar de novo -> update do detalhe): OK';
end $$;
reset role;

-- TESTE 3 — desativar / reativar (campo ativo, sem RPC)
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  update trabalhador set ativo=false where id='a1200000-0000-0000-0000-000000000002';
  if (select ativo from trabalhador where id='a1200000-0000-0000-0000-000000000002') then raise exception 'não desativou'; end if;
  update trabalhador set ativo=true where id='a1200000-0000-0000-0000-000000000002';
  if not (select ativo from trabalhador where id='a1200000-0000-0000-0000-000000000002') then raise exception 'não reativou'; end if;
  raise notice 'TESTE 3 (desativar/reativar): OK';
end $$;
reset role;

-- TESTE 4 — kiosk NÃO pode editar
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.atualizar_colaborador(p_id := 'a1200000-0000-0000-0000-000000000001', p_nome := 'X', p_area := 'cozinha');
    raise exception 'FALHA: kiosk editou colaborador';
  exception when insufficient_privilege then null; end;
  raise notice 'TESTE 4 (kiosk não edita): OK';
end $$;
reset role;

select 'ATUALIZAR COLABORADOR: TODOS OS TESTES PASSARAM' as resultado;