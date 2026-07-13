-- =====================================================================
-- 02_kiosk_admin_test.sql — Sprint 1: identidade e acesso.
-- Pré: bootstrap + 0001 + 0002 + 0003 + seed.
-- DoD: admin de empresa vê o seu; kiosk SÓ insere eventos da sua loja
--      e NÃO lê dados de gestão/histórico.
-- =====================================================================
\set ON_ERROR_STOP on

-- utilizadores de teste
insert into auth.users (id, email) values
  ('0a000000-0000-0000-0000-0000000000aa', 'admin@a.pt') on conflict do nothing;
insert into utilizador_app (id, empresa_id, ambito, loja_id) values
  ('0a000000-0000-0000-0000-0000000000aa', '11111111-1111-1111-1111-111111111111', 'empresa', null)
  on conflict do nothing;

-- claims (note o novo campo "tipo")
\set ADMIN_A '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"admin","loja_id":null}}'
\set KIOSK_CC '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo":"kiosk","loja_id":"a1100000-0000-0000-0000-000000000001"}}'

-- =====================================================================
-- TESTE 1 — admin-empresa A continua a ver a sua empresa, nada de B
-- =====================================================================
set request.jwt.claims = :'ADMIN_A';
set role authenticated;
do $$
begin
  if not public.is_admin() then raise exception 'is_admin() devia ser true'; end if;
  if (select count(*) from loja)            <> 2 then raise exception 'admin A: esperado 2 lojas';        end if;
  if (select count(*) from picagem)         <> 1 then raise exception 'admin A: esperado 1 picagem';      end if;
  if (select count(*) from utilizador_app)  <> 1 then raise exception 'admin A: esperado 1 utilizador';   end if;
  if exists (select 1 from loja where empresa_id = '22222222-2222-2222-2222-222222222222')
    then raise exception 'FUGA: admin A vê loja de B'; end if;
  raise notice 'TESTE 1 (admin-empresa A vê o seu, nada de B): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 2 — kiosk LÊ só a fatia fina (loja própria, ativos, templates)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  if not public.is_kiosk() then raise exception 'is_kiosk() devia ser true'; end if;

  -- pode ler o necessário
  if (select count(*) from loja)               <> 1 then raise exception 'kiosk: devia ver 1 loja (a sua)';     end if;
  if (select count(*) from trabalhador)        <> 2 then raise exception 'kiosk: devia ver 2 trabalhadores';    end if;
  -- checklists: o kiosk NÃO tem policy no R2a — a leitura de templates
  -- publicados entra no R2b, com o fluxo de preenchimento
  if (select count(*) from checklist_template) <> 0 then raise exception 'kiosk: não devia ver templates antes do R2b'; end if;

  -- a loja visível é mesmo a sua
  if (select id from loja) <> 'a1100000-0000-0000-0000-000000000001'
    then raise exception 'kiosk: loja visível não é a sua'; end if;

  raise notice 'TESTE 2 (kiosk lê só a fatia fina): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 3 — kiosk NÃO lê gestão nem histórico
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  if (select count(*) from empresa)        <> 0 then raise exception 'kiosk NÃO devia ler empresa';        end if;
  if (select count(*) from utilizador_app) <> 0 then raise exception 'kiosk NÃO devia ler utilizador_app'; end if;
  if (select count(*) from picagem)        <> 0 then raise exception 'kiosk NÃO devia ler histórico de picagens'; end if;
  if (select count(*) from verificacao)    <> 0 then raise exception 'kiosk NÃO devia ler histórico de verificacoes'; end if;
  if (select count(*) from notificacao)    <> 0 then raise exception 'kiosk NÃO devia ler notificacoes'; end if;
  raise notice 'TESTE 3 (kiosk não lê gestão/histórico): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 4 — kiosk INSERE eventos da SUA loja (caminho feliz)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare v_id uuid := gen_random_uuid();  -- uuid gerado no cliente (padrão outbox)
begin
  -- sem RETURNING: o kiosk não lê event tables, por isso mintamos o id localmente
  insert into verificacao (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo)
    values (v_id, '11111111-1111-1111-1111-111111111111',
            'a1200000-0000-0000-0000-000000000001',
            'a1100000-0000-0000-0000-000000000001',
            now());

  insert into picagem (empresa_id, verificacao_id, tipo)
    values ('11111111-1111-1111-1111-111111111111', v_id, 'entrada');

  raise notice 'TESTE 4 (kiosk insere verificacao+picagem da sua loja, uuid no cliente): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 5 — kiosk NÃO insere noutra loja da mesma empresa
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    insert into verificacao (empresa_id, trabalhador_id, loja_id, momento_dispositivo)
      values ('11111111-1111-1111-1111-111111111111',
              'a1200000-0000-0000-0000-000000000001',
              'a1100000-0000-0000-0000-000000000002',  -- Esplanada, NÃO é a do kiosk
              now());
    raise exception 'FALHA: kiosk inseriu na loja Esplanada';
  exception when insufficient_privilege then null;  -- esperado
  end;
  raise notice 'TESTE 5 (kiosk não insere noutra loja): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 6 — kiosk NÃO insere noutra empresa (B)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
begin
  begin
    insert into verificacao (empresa_id, trabalhador_id, loja_id, momento_dispositivo)
      values ('22222222-2222-2222-2222-222222222222',
              'b2200000-0000-0000-0000-000000000001',
              'b2100000-0000-0000-0000-000000000001', now());
    raise exception 'FALHA: kiosk inseriu na empresa B';
  exception when insufficient_privilege then null;  -- esperado (empresa_id <> empresa_atual)
  end;
  raise notice 'TESTE 6 (kiosk não insere noutra empresa): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 7 — kiosk NÃO atualiza/apaga (append-only de facto)
-- =====================================================================
set request.jwt.claims = :'KIOSK_CC';
set role authenticated;
do $$
declare n int;
begin
  update trabalhador set nome = 'hack';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'kiosk conseguiu ATUALIZAR % trabalhadores', n; end if;

  delete from trabalhador;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'kiosk conseguiu APAGAR % trabalhadores', n; end if;

  raise notice 'TESTE 7 (kiosk não atualiza/apaga): OK';
end $$;
reset role;

select 'SPRINT 1 (identidade/kiosk): TODOS OS TESTES PASSARAM' as resultado;
