-- =====================================================================
-- 06_registar_picagem_test.sql
-- Fluxo atual (fase 2 + bilhete + idempotência + sequência):
--   iniciar_picagem(codigo, pin) -> bilhete -> registar_picagem(bilhete,
--   tipo, momento, chave_idempotencia).
-- Corre dentro de uma transação e faz rollback no fim (não deixa dados).
-- =====================================================================
\set ON_ERROR_STOP on

\set KIOSK_CC '{"sub":"cc000000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'
\set ADMIN_A  '{"sub":"aaaa0000-0000-0000-0000-000000000001","app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'

begin;

-- ---------------------------------------------------------------------
-- Setup (superuser, fora de RLS): PINs, conta kiosk registada e ativa,
-- e neutralizar a entrada do seed (anulada — o trigger de imutabilidade
-- só permite alterar colunas de anulação) para o dia começar limpo.
-- ---------------------------------------------------------------------
update trabalhador set pin = '1234', area = 'cozinha'
  where id = 'a1200000-0000-0000-0000-000000000001';
update trabalhador set pin = '5678', ativo = false
  where id = 'a1200000-0000-0000-0000-000000000002';

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

-- TESTE 1 — caminho feliz: iniciar (bilhete) + registar entrada
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare
  v_json json;
  v_aut  uuid;
  v_res  json;
  v_vid  uuid;
begin
  v_json := public.iniciar_picagem('1001', '1234');
  if (v_json ->> 'nome') is null then raise exception 'nome não devolvido'; end if;
  v_aut := (v_json ->> 'autorizacao_id')::uuid;
  if v_aut is null then raise exception 'bilhete não emitido'; end if;

  v_res := public.registar_picagem(v_aut, 'entrada',
             now() - interval '90 minutes',
             '0c000000-0000-0000-0000-0000000000c1'::uuid);
  v_vid := (v_res ->> 'verificacao_id')::uuid;
  if v_vid is null then raise exception 'verificacao não devolvida'; end if;
  if (v_res ->> 'repetida')::boolean then raise exception 'não devia ser repetida'; end if;

  reset role;
  if (select count(*) from verificacao where id = v_vid) <> 1 then raise exception 'verificacao não criada'; end if;
  if (select loja_id from verificacao where id = v_vid) <> 'a1100000-0000-0000-0000-000000000001' then raise exception 'loja errada (devia vir do JWT)'; end if;
  if (select trabalhador_id from verificacao where id = v_vid) <> 'a1200000-0000-0000-0000-000000000001' then raise exception 'trabalhador errado (devia vir do bilhete)'; end if;
  if (select momento_servidor from verificacao where id = v_vid) is null then raise exception 'momento_servidor não preenchido'; end if;
  if (select tipo from picagem where verificacao_id = v_vid) <> 'entrada' then raise exception 'picagem não criada'; end if;
  if (select usada_em from autorizacao where id = v_aut) is null then raise exception 'bilhete não consumido'; end if;
  raise notice 'TESTE 1 (bilhete + entrada caminho feliz): OK';
end $$;
reset role;

-- TESTE 2 — PIN errado: iniciar_picagem rejeita, nenhum bilhete emitido
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.iniciar_picagem('1001', '0000');
    raise exception 'FALHA: aceitou PIN errado';
  exception when invalid_authorization_specification then null; end;
  raise notice 'TESTE 2 (PIN errado rejeitado): OK';
end $$;
reset role;

-- TESTE 3 — trabalhador inativo (Bruno): iniciar_picagem rejeita
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.iniciar_picagem('1002', '5678');
    raise exception 'FALHA: aceitou trabalhador inativo';
  exception when invalid_authorization_specification then null; end;
  raise notice 'TESTE 3 (inativo rejeitado): OK';
end $$;
reset role;

-- TESTE 4 — tipo inválido (validado antes de tocar no bilhete)
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.registar_picagem(gen_random_uuid(), 'almoço', now(), gen_random_uuid());
    raise exception 'FALHA: aceitou tipo inválido';
  exception when others then
    if sqlerrm not like '%tipo de picagem inválido%' then raise; end if;
  end;
  raise notice 'TESTE 4 (tipo inválido rejeitado): OK';
end $$;
reset role;

-- TESTE 5 — bilhete já utilizado: reutilizar o do TESTE 1 falha
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_aut uuid;
begin
  reset role;
  select id into v_aut from autorizacao
   where trabalhador_id = 'a1200000-0000-0000-0000-000000000001' and usada_em is not null
   order by criada_em desc limit 1;
  set role authenticated;
  begin
    perform public.registar_picagem(v_aut, 'saida', now(), gen_random_uuid());
    raise exception 'FALHA: aceitou bilhete já utilizado';
  exception when invalid_authorization_specification then
    if sqlerrm not like '%utilizada%' then raise; end if;
  end;
  raise notice 'TESTE 5 (bilhete de uso único): OK';
end $$;
reset role;

-- TESTE 6 — idempotência: repetir a chave do TESTE 1 devolve o existente
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_json json; v_res json;
begin
  v_json := public.iniciar_picagem('1001', '1234');
  v_res := public.registar_picagem(
             (v_json ->> 'autorizacao_id')::uuid, 'entrada',
             now(), '0c000000-0000-0000-0000-0000000000c1'::uuid);
  if not (v_res ->> 'repetida')::boolean then raise exception 'devia ser repetida'; end if;
  reset role;
  if (select count(*) from verificacao
       where chave_idempotencia = '0c000000-0000-0000-0000-0000000000c1'::uuid) <> 1
    then raise exception 'duplicou apesar da chave'; end if;
  raise notice 'TESTE 6 (idempotência por chave): OK';
end $$;
reset role;

-- TESTE 7 — sequência inválida: entrada após entrada é recusada
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_json json;
begin
  v_json := public.iniciar_picagem('1001', '1234');
  begin
    perform public.registar_picagem(
      (v_json ->> 'autorizacao_id')::uuid, 'entrada', now(), gen_random_uuid());
    raise exception 'FALHA: aceitou entrada após entrada';
  exception when invalid_authorization_specification then
    if sqlerrm not like '%sequência%' then raise; end if;
  end;
  raise notice 'TESTE 7 (sequência inválida rejeitada): OK';
end $$;
reset role;

-- TESTE 8 — não-kiosk (admin) não pode iniciar picagem
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  begin
    perform public.iniciar_picagem('1001', '1234');
    raise exception 'FALHA: admin iniciou picagem';
  exception when insufficient_privilege then null; end;
  raise notice 'TESTE 8 (não-kiosk bloqueado): OK';
end $$;
reset role;

rollback;

select 'REGISTAR PICAGEM: TODOS OS TESTES PASSARAM' as resultado;
