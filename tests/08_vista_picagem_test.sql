-- =====================================================================
-- 08_vista_picagem_test.sql
-- =====================================================================
\set ON_ERROR_STOP on
update trabalhador set pin='1234' where id='a1200000-0000-0000-0000-000000000001';

\set KIOSK_CC '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'
\set ADMIN_A  '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'

-- registar uma picagem (via kiosk) para haver dados
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
select public.registar_picagem(
  '0c000000-0000-0000-0000-0000000000d1', '1001', '1234', 'entrada', now(),
  '11111111-1111-1111-1111-111111111111/a1100000-0000-0000-0000-000000000001/foto.jpg');
reset role;

-- TESTE 1 — admin vê a picagem na vista, com nome e loja
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
declare r record;
begin
  select * into r from public.vista_picagem where picagem_id is not null limit 1;
  if r.trabalhador_nome is null then raise exception 'vista sem nome do trabalhador'; end if;
  if r.loja_nome <> 'Cozinha Central' then raise exception 'loja errada na vista: %', r.loja_nome; end if;
  if r.tipo <> 'entrada' then raise exception 'tipo errado'; end if;
  raise notice 'TESTE 1 (admin vê vista: % / % / %): OK', r.trabalhador_nome, r.loja_nome, r.tipo;
end $$;
reset role;

-- TESTE 2 — kiosk NÃO vê linhas na vista (sem SELECT nas tabelas de evento)
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.vista_picagem;
  if n <> 0 then raise exception 'FUGA: kiosk viu % linhas na vista', n; end if;
  raise notice 'TESTE 2 (kiosk não vê a vista): OK';
end $$;
reset role;

-- TESTE 3 — a vista não traz a coluna pin
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vista_picagem' and column_name='pin'
  ) then raise exception 'vista expõe pin'; end if;
  raise notice 'TESTE 3 (vista não expõe pin): OK';
end $$;

select 'VISTA PICAGEM: TODOS OS TESTES PASSARAM' as resultado;
