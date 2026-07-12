-- =====================================================================
-- 08_vista_picagem_test.sql
-- Usa o fluxo atual (iniciar_picagem -> bilhete -> registar_picagem) para
-- criar dados; corre dentro de uma transação e faz rollback no fim.
-- =====================================================================
\set ON_ERROR_STOP on

\set KIOSK_CC '{"sub":"cc000000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'
\set ADMIN_A  '{"sub":"aaaa0000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'

begin;

-- Setup (superuser): PIN, conta kiosk, seed neutralizado (dia limpo).
update trabalhador set pin = '1234'
  where id = 'a1200000-0000-0000-0000-000000000001';
insert into auth.users (id, email, raw_app_meta_data) values
  ('cc000000-0000-0000-0000-000000000001', 'kiosk-cc@teste.local',
   '{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}'::jsonb)
  on conflict (id) do nothing;
insert into public.kiosk (id, empresa_id, loja_id, ativo) values
  ('cc000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'a1100000-0000-0000-0000-000000000001', true)
  on conflict (id) do nothing;
-- Dia limpo: anular TODAS as picagens vivas da empresa A (o seed e testes
-- anteriores sem rollback deixam picagens de hoje; com o P1 as anuladas
-- deixam de contar para a sequência). Tudo revertido no rollback final.
update picagem set anulada = true, anulada_em = now(),
                   motivo_anulacao = 'setup do teste: dia limpo'
  where empresa_id = '11111111-1111-1111-1111-111111111111' and not anulada;

-- registar uma picagem (via kiosk, fluxo do bilhete) para haver dados
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_json json;
begin
  v_json := public.iniciar_picagem('1001', '1234');
  perform public.registar_picagem(
    (v_json ->> 'autorizacao_id')::uuid, 'entrada', now(), gen_random_uuid());
end $$;
reset role;

-- TESTE 1 — admin vê a picagem na vista, com nome e loja
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
declare r record;
begin
  select * into r from public.vista_picagem
   where not anulada order by momento_dispositivo desc limit 1;
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

rollback;

select 'VISTA PICAGEM: TODOS OS TESTES PASSARAM' as resultado;
