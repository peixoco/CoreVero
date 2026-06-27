-- =====================================================================
-- 06_registar_picagem_test.sql
-- =====================================================================
\set ON_ERROR_STOP on

-- Dar PIN à Ana (1001) para o teste; superuser, fora de RLS.
update trabalhador set pin = '1234', area = 'cozinha'
  where id = 'a1200000-0000-0000-0000-000000000001';
-- Bruno (1002) fica inativo para testar o caminho de inativo
update trabalhador set pin = '5678', ativo = false
  where id = 'a1200000-0000-0000-0000-000000000002';

\set KIOSK_CC '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'
\set ADMIN_A  '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'

-- TESTE 1 — caminho feliz: kiosk regista uma entrada da Ana
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_vid uuid := '0c000000-0000-0000-0000-0000000000e1';
begin
  perform public.registar_picagem(
    p_verificacao_id := v_vid,
    p_codigo_pessoal := '1001', p_pin := '1234',
    p_tipo := 'entrada',
    p_momento_dispositivo := now() - interval '2 minutes',
    p_foto_url := '11111111-1111-1111-1111-111111111111/a1100000-0000-0000-0000-000000000001/'||v_vid||'.jpg'
  );
  reset role;
  -- verificar como superuser que ficaram as duas linhas certas
  if (select count(*) from verificacao where id = v_vid) <> 1 then raise exception 'verificacao não criada'; end if;
  if (select loja_id from verificacao where id = v_vid) <> 'a1100000-0000-0000-0000-000000000001' then raise exception 'loja errada (devia vir do JWT)'; end if;
  if (select trabalhador_id from verificacao where id = v_vid) <> 'a1200000-0000-0000-0000-000000000001' then raise exception 'trabalhador errado'; end if;
  if (select momento_servidor from verificacao where id = v_vid) is null then raise exception 'momento_servidor não preenchido'; end if;
  if (select tipo from picagem where verificacao_id = v_vid) <> 'entrada' then raise exception 'picagem não criada'; end if;
  raise notice 'TESTE 1 (entrada caminho feliz): OK';
end $$;

-- TESTE 2 — PIN errado: rejeita, nada inserido
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_vid uuid := '0c000000-0000-0000-0000-0000000000e2';
begin
  begin
    perform public.registar_picagem(v_vid, '1001', '0000', 'entrada', now(), 'x/y/'||v_vid||'.jpg');
    raise exception 'FALHA: aceitou PIN errado';
  exception when invalid_authorization_specification then null; end;
  reset role;
  if (select count(*) from verificacao where id = v_vid) <> 0 then raise exception 'inseriu apesar de PIN errado'; end if;
  raise notice 'TESTE 2 (PIN errado rejeitado): OK';
end $$;

-- TESTE 3 — trabalhador inativo (Bruno): rejeita
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.registar_picagem('0c000000-0000-0000-0000-0000000000e3', '1002', '5678', 'entrada', now(), 'x/y/z.jpg');
    raise exception 'FALHA: aceitou trabalhador inativo';
  exception when invalid_authorization_specification then null; end;
  raise notice 'TESTE 3 (inativo rejeitado): OK';
end $$;
reset role;

-- TESTE 4 — tipo inválido
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.registar_picagem('0c000000-0000-0000-0000-0000000000e4', '1001', '1234', 'almoço', now(), 'x/y/z.jpg');
    raise exception 'FALHA: aceitou tipo inválido';
  exception when others then
    if sqlerrm not like '%tipo de picagem inválido%' then raise; end if;
  end;
  raise notice 'TESTE 4 (tipo inválido rejeitado): OK';
end $$;
reset role;

-- TESTE 5 — foto em falta
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    perform public.registar_picagem('0c000000-0000-0000-0000-0000000000e5', '1001', '1234', 'entrada', now(), '');
    raise exception 'FALHA: aceitou sem foto';
  exception when others then
    if sqlerrm not like '%foto obrigatória%' then raise; end if;
  end;
  raise notice 'TESTE 5 (foto obrigatória): OK';
end $$;
reset role;

-- TESTE 6 — não-kiosk (admin) não pode registar
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  begin
    perform public.registar_picagem('0c000000-0000-0000-0000-0000000000e6', '1001', '1234', 'entrada', now(), 'x/y/z.jpg');
    raise exception 'FALHA: admin registou picagem';
  exception when insufficient_privilege then null; end;
  raise notice 'TESTE 6 (não-kiosk bloqueado): OK';
end $$;
reset role;

-- TESTE 7 — intervalos (CT art. 202): inicio_intervalo aceite
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_vid uuid := '0c000000-0000-0000-0000-0000000000e7';
begin
  perform public.registar_picagem(v_vid, '1001', '1234', 'inicio_intervalo', now(), 'a/b/'||v_vid||'.jpg');
  reset role;
  if (select tipo from picagem where verificacao_id = v_vid) <> 'inicio_intervalo' then raise exception 'intervalo não registado'; end if;
  raise notice 'TESTE 7 (inicio_intervalo aceite): OK';
end $$;
reset role;

select 'REGISTAR PICAGEM: TODOS OS TESTES PASSARAM' as resultado;
