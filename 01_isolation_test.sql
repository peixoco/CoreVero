-- =====================================================================
-- 01_isolation_test.sql — Teste verificável de isolamento multi-tenant.
-- Corre depois de: bootstrap + 0001 + 0002 + seed.
-- Aborta com RAISE EXCEPTION ao primeiro falhanço; se chegar ao fim,
-- imprime "ISOLAMENTO: TODOS OS TESTES PASSARAM".
--
-- Roles: corre como authenticated (NÃO é owner nem superuser) -> a RLS
-- aplica-se. O claim entra via GUC request.jwt.claims (= o que o Supabase
-- preenche a partir do JWT verificado).
-- =====================================================================

\set ON_ERROR_STOP on

-- IDs dos tenants (ver seed.sql)
\set A '11111111-1111-1111-1111-111111111111'
\set B '22222222-2222-2222-2222-222222222222'

-- ---- preâmbulo como superuser: utilizadores de teste (um por tenant) ----
insert into auth.users (id, email) values
  ('0a000000-0000-0000-0000-0000000000aa', 'admin@empresa-a.pt'),
  ('0b000000-0000-0000-0000-0000000000bb', 'admin@empresa-b.pt')
on conflict do nothing;

insert into utilizador_app (id, empresa_id, ambito, loja_id) values
  ('0a000000-0000-0000-0000-0000000000aa', :'A', 'empresa', null),
  ('0b000000-0000-0000-0000-0000000000bb', :'B', 'empresa', null)
on conflict do nothing;

-- =====================================================================
-- TESTE 1 — Empresa A vê só o seu (contagens exatas + zero da B)
-- =====================================================================
set request.jwt.claims = '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111"}}';
set role authenticated;

do $$
begin
  -- confirma que a função lê o claim
  if public.empresa_atual() <> '11111111-1111-1111-1111-111111111111'
    then raise exception 'empresa_atual() não leu o claim de A'; end if;

  -- contagens visíveis = exatamente as de A
  if (select count(*) from empresa)            <> 1 then raise exception 'A/empresa: esperado 1';            end if;
  if (select count(*) from loja)               <> 2 then raise exception 'A/loja: esperado 2';               end if;
  if (select count(*) from trabalhador)        <> 2 then raise exception 'A/trabalhador: esperado 2';        end if;
  if (select count(*) from trabalhador_loja)   <> 1 then raise exception 'A/trabalhador_loja: esperado 1';   end if;
  if (select count(*) from verificacao)        <> 1 then raise exception 'A/verificacao: esperado 1';        end if;
  if (select count(*) from picagem)            <> 1 then raise exception 'A/picagem: esperado 1';            end if;
  if (select count(*) from checklist_template) <> 1 then raise exception 'A/checklist_template: esperado 1'; end if;
  if (select count(*) from checklist_item)     <> 2 then raise exception 'A/checklist_item: esperado 2';     end if;
  if (select count(*) from utilizador_app)     <> 1 then raise exception 'A/utilizador_app: esperado 1';     end if;

  -- ZERO linhas da B, em todas as tabelas (a fuga clássica)
  if exists (select 1 from empresa            where id         = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê empresa B';            end if;
  if exists (select 1 from loja               where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê loja de B';            end if;
  if exists (select 1 from trabalhador        where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê trabalhador de B';     end if;
  if exists (select 1 from verificacao        where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê verificacao de B';     end if;
  if exists (select 1 from picagem            where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê picagem de B';         end if;
  if exists (select 1 from checklist_template where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê checklist_template B';  end if;
  if exists (select 1 from checklist_item     where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê checklist_item de B';   end if;
  if exists (select 1 from utilizador_app     where empresa_id = '22222222-2222-2222-2222-222222222222') then raise exception 'FUGA: A vê utilizador_app de B';   end if;

  -- acesso direto por id conhecido de B -> 0 linhas
  if exists (select 1 from loja where id = 'b2100000-0000-0000-0000-000000000001')
    then raise exception 'FUGA: A leu loja de B por id direto'; end if;

  raise notice 'TESTE 1 (A vê só o seu + zero de B): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 2 — Empresa B vê só o seu (simétrico)
-- =====================================================================
set request.jwt.claims = '{"app_metadata":{"empresa_id":"22222222-2222-2222-2222-222222222222"}}';
set role authenticated;

do $$
begin
  if (select count(*) from loja)        <> 1 then raise exception 'B/loja: esperado 1';        end if;
  if (select count(*) from trabalhador) <> 1 then raise exception 'B/trabalhador: esperado 1'; end if;
  if exists (select 1 from loja where empresa_id = '11111111-1111-1111-1111-111111111111')
    then raise exception 'FUGA: B vê loja de A'; end if;
  raise notice 'TESTE 2 (B vê só o seu): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 3 — Escrita cross-tenant barrada (WITH CHECK)
-- Como A, inserir uma loja com empresa_id=B tem de falhar (42501).
-- Inserir na própria empresa (A) tem de funcionar.
-- =====================================================================
set request.jwt.claims = '{"app_metadata":{"empresa_id":"11111111-1111-1111-1111-111111111111"}}';
set role authenticated;

do $$
begin
  -- tentativa cross-tenant: deve falhar
  begin
    insert into loja (empresa_id, nome, ativa)
      values ('22222222-2222-2222-2222-222222222222', 'loja injetada', true);
    raise exception 'FALHA DE SEGURANÇA: A escreveu uma loja no tenant B';
  exception
    when insufficient_privilege then null;  -- "violates row-level security policy" -> esperado
  end;

  -- escrita na própria empresa: deve funcionar
  insert into loja (empresa_id, nome, ativa)
    values ('11111111-1111-1111-1111-111111111111', 'loja legítima de A', true);
  if (select count(*) from loja) <> 3 then raise exception 'A devia ver 3 lojas após inserir'; end if;

  raise notice 'TESTE 3 (escrita cross-tenant barrada, escrita própria OK): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 4 — Sem claim válido -> RLS nega tudo (fail-closed)
-- authenticated com claim vazio -> empresa_atual()=NULL -> 0 linhas.
-- =====================================================================
set request.jwt.claims = '';
set role authenticated;

do $$
begin
  if public.empresa_atual() is not null then raise exception 'empresa_atual() devia ser NULL sem claim'; end if;
  if (select count(*) from loja)        <> 0 then raise exception 'Sem claim devia ver 0 lojas';        end if;
  if (select count(*) from empresa)     <> 0 then raise exception 'Sem claim devia ver 0 empresas';     end if;
  if (select count(*) from verificacao) <> 0 then raise exception 'Sem claim devia ver 0 verificacoes'; end if;
  raise notice 'TESTE 4 (sem claim -> 0 linhas, fail-closed): OK';
end $$;
reset role;

-- =====================================================================
-- TESTE 5 — Garantia ESTRUTURAL (FK composta), independente da RLS.
-- Como superuser (bypassa RLS), uma picagem no tenant A não pode
-- referenciar uma verificacao do tenant B: a FK (empresa_id, verificacao_id)
-- não encontra a linha -> erro de integridade referencial.
-- =====================================================================
do $$
begin
  begin
    insert into picagem (empresa_id, verificacao_id, tipo)
      values ('11111111-1111-1111-1111-111111111111',
              'b2300000-0000-0000-0000-000000000001',  -- verificacao de B
              'entrada');
    raise exception 'FALHA ESTRUTURAL: picagem de A referenciou verificacao de B';
  exception
    when foreign_key_violation then null;  -- esperado
  end;
  raise notice 'TESTE 5 (FK composta impede referência cross-tenant): OK';
end $$;

select 'ISOLAMENTO: TODOS OS TESTES PASSARAM' as resultado;
