-- =====================================================================
-- 07_sequencia_anuladas_test.sql
-- P1 (R0): sequencia_valida e iniciar_picagem excluem picagens ANULADAS.
-- Cenário real: trabalhador pica entrada, o admin anula-a; o trabalhador
-- tem de poder picar entrada outra vez (a anulada não conta como última).
-- Corre dentro de uma transação e faz rollback no fim.
-- =====================================================================
\set ON_ERROR_STOP on

\set KIOSK_CC '{"sub":"cc000000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'
\set ADMIN_A  '{"sub":"aaaa0000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'

begin;

-- Setup (superuser): igual ao 06 — PIN da Ana, conta kiosk, seed neutralizado.
update trabalhador set pin = '1234'
  where id = 'a1200000-0000-0000-0000-000000000001';
insert into auth.users (id, email, raw_app_meta_data) values
  ('cc000000-0000-0000-0000-000000000001', 'kiosk-cc@teste.local',
   '{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}'::jsonb)
  on conflict (id) do nothing;
insert into auth.users (id, email) values
  ('aaaa0000-0000-0000-0000-000000000001', 'admin-a@teste.local')
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

-- TESTE 1 — kiosk regista uma entrada (fica como última do dia)
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_json json;
begin
  v_json := public.iniciar_picagem('1001', '1234');
  perform public.registar_picagem(
    (v_json ->> 'autorizacao_id')::uuid, 'entrada',
    now() - interval '90 minutes',
    '0c000000-0000-0000-0000-0000000000a1'::uuid);
  raise notice 'TESTE 1 (entrada registada): OK';
end $$;
reset role;

-- TESTE 2 — controlo negativo: com a entrada VIVA, nova entrada é inválida
do $$
begin
  if public.sequencia_valida(
       '11111111-1111-1111-1111-111111111111',
       'a1200000-0000-0000-0000-000000000001', 'entrada', now())
  then raise exception 'FALHA: aceitou entrada após entrada viva'; end if;
  raise notice 'TESTE 2 (entrada viva bloqueia nova entrada): OK';
end $$;

-- TESTE 3 — o admin anula a entrada
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
declare v_pid uuid;
begin
  reset role;
  select p.id into v_pid
    from picagem p join verificacao v on v.id = p.verificacao_id
   where v.chave_idempotencia = '0c000000-0000-0000-0000-0000000000a1'::uuid;
  set role authenticated;
  set request.jwt.claims = '{"sub":"aaaa0000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}';
  perform public.anular_picagem(v_pid, 'teste P1: anulada não deve contar na sequência');
  reset role;
  if not (select anulada from picagem where id = v_pid) then raise exception 'não anulou'; end if;
  raise notice 'TESTE 3 (admin anulou a entrada): OK';
end $$;
reset role;

-- TESTE 4 — P1 em sequencia_valida: a anulada NÃO conta; entrada volta a ser válida
do $$
begin
  if not public.sequencia_valida(
       '11111111-1111-1111-1111-111111111111',
       'a1200000-0000-0000-0000-000000000001', 'entrada', now())
  then raise exception 'FALHA P1: sequencia_valida ainda conta a picagem anulada'; end if;
  raise notice 'TESTE 4 (sequencia_valida ignora anuladas): OK';
end $$;

-- TESTE 5 — P1 em iniciar_picagem: a última do dia devolvida ao kiosk ignora a anulada
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_json json;
begin
  v_json := public.iniciar_picagem('1001', '1234');
  if (v_json ->> 'ultima_tipo') is not null then
    raise exception 'FALHA P1: iniciar_picagem devolveu a anulada como última (%)', v_json ->> 'ultima_tipo';
  end if;

  -- TESTE 6 — fim-a-fim: nova entrada é aceite pelo servidor
  perform public.registar_picagem(
    (v_json ->> 'autorizacao_id')::uuid, 'entrada', now(), gen_random_uuid());
  raise notice 'TESTE 5 (iniciar_picagem ignora anuladas): OK';
  raise notice 'TESTE 6 (nova entrada aceite após anulação): OK';
end $$;
reset role;

rollback;

select 'SEQUÊNCIA vs ANULADAS (P1): TODOS OS TESTES PASSARAM' as resultado;
