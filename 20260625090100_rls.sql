-- =====================================================================
-- 0002_rls.sql — Isolamento multi-tenant (doc 01 §4)
-- RLS ativa em TODAS as tabelas de domínio + policy-tipo uniforme.
-- =====================================================================

-- ---------------------------------------------------------------------
-- empresa_atual() — lê o claim empresa_id do JWT verificado.
--
-- Em Supabase o JWT verificado é colocado por baixo no GUC de sessão
-- 'request.jwt.claims'. auth.jwt() do Supabase devolve exatamente este
-- JSON; lemos o GUC diretamente para que a função-núcleo de segurança
-- NÃO dependa do schema auth (uma dependência a menos no caminho crítico).
--   Equivalente a:  auth.jwt() -> 'app_metadata' ->> 'empresa_id'
--
-- empresa_id vive em app_metadata (não manipulável pelo utilizador).
-- Sem claim / claim vazio -> NULL -> a policy nega tudo (fail-closed).
-- ---------------------------------------------------------------------
create or replace function public.empresa_atual()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(
           nullif(current_setting('request.jwt.claims', true), '')::jsonb
             -> 'app_metadata' ->> 'empresa_id',
           ''
         )::uuid
$$;

grant execute on function public.empresa_atual() to authenticated, anon;

-- ---------------------------------------------------------------------
-- Privilégios de tabela (a RLS é que filtra por tenant; estes grants
-- apenas habilitam o role a operar — Sprint 1 afina por comando/role).
-- ---------------------------------------------------------------------
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- ---------------------------------------------------------------------
-- RLS + policy-tipo. Tabelas de domínio: empresa_id = empresa_atual().
-- A tabela `empresa` é especial: filtra pelo seu próprio id.
-- Policies `to authenticated`: anon (e qualquer role sem policy) -> negado.
-- ---------------------------------------------------------------------

-- empresa (filtra por id, não empresa_id)
alter table empresa enable row level security;
create policy tenant_isolation on empresa
  for all to authenticated
  using      (id = public.empresa_atual())
  with check (id = public.empresa_atual());

-- restantes tabelas de domínio: policy idêntica sobre empresa_id
do $$
declare t text;
begin
  foreach t in array array[
    'loja','trabalhador','trabalhador_loja','verificacao','picagem',
    'checklist_template','checklist_template_loja','checklist_item',
    'checklist_instancia','checklist_resposta','acao_corretiva',
    'notificacao','utilizador_app'
  ]
  loop
    execute format('alter table %I enable row level security;', t);
    execute format($f$
      create policy tenant_isolation on %I
        for all to authenticated
        using      (empresa_id = public.empresa_atual())
        with check (empresa_id = public.empresa_atual());
    $f$, t);
  end loop;
end $$;
