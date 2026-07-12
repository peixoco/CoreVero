-- P4-pré/P9 (doc 09 v2): criar_colaborador, gerar_novo_pin e atualizar_colaborador
-- eram SECURITY INVOKER e dependiam de grants de escrita na coluna trabalhador.pin
-- detidos por authenticated (grant de tabela inteira do Sprint 0). Enquanto assim
-- fosse, qualquer sessão autenticada podia escrever PINs por query direta (dentro
-- do âmbito RLS da sua empresa).
--
-- Alteração:
--   1. As três funções passam a SECURITY DEFINER + set search_path to ''.
--      Um definer ignora RLS, portanto a verificação interna deixa de ser
--      opcional: is_admin() + escopo explícito por empresa_atual() em todas
--      as queries (padrão das RPCs definer existentes, ex. corrigir_picagem_bloco).
--      Os corpos mantêm-se funcionalmente idênticos; acrescenta-se apenas o
--      guard de empresa nula onde faltava (gerar_novo_pin, atualizar_colaborador).
--   2. Fecha-se a escrita direta do PIN: revoke por coluna e, como o privilégio
--      vem de um grant de TABELA (20260625090100_rls.sql), reestrutura-se —
--      revoke insert/update de tabela + grant por coluna em todas exceto pin.
--      (Espelha o que 20260627120000_pin_credencial.sql fez para o SELECT.)
-- Nenhuma assinatura muda; tipos gerados não são afetados.

-- ---------------------------------------------------------------------
-- 1a. criar_colaborador -> DEFINER (corpo idêntico ao de 20260626130000)
-- ---------------------------------------------------------------------
create or replace function public.criar_colaborador(
  p_nome             text,
  p_area             text,
  p_nome_completo    text  default null,
  p_posicao          text  default null,
  p_contrato_inicio  date  default null,
  p_contrato_fim     date  default null,
  p_telefone         text  default null,
  p_email            text  default null,
  p_data_nascimento  date  default null
)
returns table (trabalhador_id uuid, codigo_pessoal text, pin text)
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_empresa uuid := public.empresa_atual();
  v_id      uuid := gen_random_uuid();
  v_pin     text;
  v_codigo  text;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem criar colaboradores'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null then
    raise exception 'sem empresa no contexto de sessão';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'nome é obrigatório';
  end if;
  if coalesce(trim(p_area), '') = '' then
    raise exception 'área é obrigatória';
  end if;

  -- PIN: 4 dígitos no servidor (colisões são aceitáveis — a foto é a prova)
  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  -- codigo_pessoal: próximo número livre da empresa (mín. 1001)
  select (coalesce(max(t.codigo_pessoal::int), 1000) + 1)::text
    into v_codigo
    from public.trabalhador t
   where t.empresa_id = v_empresa
     and t.codigo_pessoal ~ '^[0-9]+$';

  -- camada kiosk
  insert into public.trabalhador (id, empresa_id, nome, codigo_pessoal, pin, area, ativo)
  values (v_id, v_empresa, p_nome, v_codigo, v_pin, p_area, true);

  -- camada RH (identificação/contrato)
  insert into public.trabalhador_detalhe
    (trabalhador_id, empresa_id, nome_completo, data_nascimento, posicao,
     telefone, email, contrato_inicio, contrato_fim)
  values
    (v_id, v_empresa, p_nome_completo, p_data_nascimento, p_posicao,
     p_telefone, p_email, p_contrato_inicio, p_contrato_fim);

  return query select v_id, v_codigo, v_pin;
end $$;

-- ---------------------------------------------------------------------
-- 1b. gerar_novo_pin -> DEFINER (corpo idêntico + guard de empresa nula)
-- ---------------------------------------------------------------------
create or replace function public.gerar_novo_pin(p_trabalhador_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_empresa uuid := public.empresa_atual();
  v_pin     text;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem gerar PIN'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null then
    raise exception 'sem empresa no contexto de sessão';
  end if;
  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  update public.trabalhador
     set pin = v_pin
   where id = p_trabalhador_id
     and empresa_id = v_empresa;
  if not found then
    raise exception 'colaborador não encontrado nesta empresa';
  end if;
  return v_pin;
end $$;

-- ---------------------------------------------------------------------
-- 1c. atualizar_colaborador -> DEFINER (corpo idêntico + guard de empresa nula)
-- ---------------------------------------------------------------------
create or replace function public.atualizar_colaborador(
  p_id               uuid,
  p_nome             text,
  p_area             text,
  p_nome_completo    text  default null,
  p_data_nascimento  date  default null,
  p_posicao          text  default null,
  p_contrato_inicio  date  default null,
  p_contrato_fim     date  default null,
  p_telefone         text  default null,
  p_email            text  default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare v_empresa uuid := public.empresa_atual();
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem editar colaboradores'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null then
    raise exception 'sem empresa no contexto de sessão';
  end if;
  if coalesce(trim(p_nome), '') = '' then raise exception 'nome é obrigatório'; end if;
  if coalesce(trim(p_area), '') = '' then raise exception 'área é obrigatória'; end if;

  update public.trabalhador
     set nome = p_nome, area = p_area
   where id = p_id and empresa_id = v_empresa;
  if not found then
    raise exception 'colaborador não encontrado nesta empresa';
  end if;

  insert into public.trabalhador_detalhe
    (trabalhador_id, empresa_id, nome_completo, data_nascimento, posicao,
     telefone, email, contrato_inicio, contrato_fim)
  values
    (p_id, v_empresa, p_nome_completo, p_data_nascimento, p_posicao,
     p_telefone, p_email, p_contrato_inicio, p_contrato_fim)
  on conflict (trabalhador_id) do update set
    nome_completo   = excluded.nome_completo,
    data_nascimento = excluded.data_nascimento,
    posicao         = excluded.posicao,
    telefone        = excluded.telefone,
    email           = excluded.email,
    contrato_inicio = excluded.contrato_inicio,
    contrato_fim    = excluded.contrato_fim;
end $$;

-- ---------------------------------------------------------------------
-- 2. Execução: padrão das RPCs definer do repo (revoke public, grant
--    authenticated). CREATE OR REPLACE preserva ACLs antigas — que
--    incluíam EXECUTE a PUBLIC por defeito das funções invoker originais.
-- ---------------------------------------------------------------------
revoke all on function
  public.criar_colaborador(text, text, text, text, date, date, text, text, date),
  public.gerar_novo_pin(uuid),
  public.atualizar_colaborador(uuid, text, text, text, date, text, date, date, text, text)
  from public, anon;

grant execute on function
  public.criar_colaborador(text, text, text, text, date, date, text, text, date),
  public.gerar_novo_pin(uuid),
  public.atualizar_colaborador(uuid, text, text, text, date, text, date, date, text, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 3. Fechar a escrita direta do PIN por clientes.
--    Primeiro o revoke por coluna (cobre grants column-level que existam)...
-- ---------------------------------------------------------------------
revoke insert (pin), update (pin), references (pin) on public.trabalhador from authenticated;

-- ---------------------------------------------------------------------
-- 4. ...e como o INSERT/UPDATE vinham de um grant de TABELA
--    (20260625090100_rls.sql: grant ... on all tables), reestrutura-se:
--    revoke de tabela + grant por coluna em todas as colunas exceto pin.
--    Colunas de trabalhador: id, empresa_id, nome, codigo_pessoal, ativo,
--    created_at, pin, area (20260625090000_schema.sql + 20260626110000).
-- ---------------------------------------------------------------------
revoke insert, update on public.trabalhador from authenticated;

grant insert (id, empresa_id, nome, codigo_pessoal, ativo, created_at, area),
      update (id, empresa_id, nome, codigo_pessoal, ativo, created_at, area)
  on public.trabalhador
  to authenticated;
