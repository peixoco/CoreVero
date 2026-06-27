-- =====================================================================
-- 20260626130000_criar_colaborador.sql
-- RPC atómica para criar um colaborador (ficha de identificação/contrato).
-- Escreve em trabalhador (kiosk) + trabalhador_detalhe (RH) numa única
-- transação. PIN gerado no servidor. SECURITY INVOKER -> respeita a RLS
-- (só admin, e só na sua empresa).
--
-- Dados sensíveis (NIF/NISS/IBAN, documentos, aptidão médica) NÃO entram
-- aqui — vão para estruturas próprias com role/cifra/retenção dedicados
-- (doc 06 §8), depois do parecer jurídico.
-- =====================================================================

-- ---------------------------------------------------------------------
-- criar_colaborador — devolve id + codigo_pessoal + pin (para o admin
-- comunicar ao colaborador). O codigo_pessoal é gerado sequencialmente
-- por empresa; o pin é aleatório de 4 dígitos (não derivado de dados pessoais).
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
security invoker
set search_path = ''
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
-- gerar_novo_pin — regenera o PIN de um colaborador (admin), devolve-o.
-- ---------------------------------------------------------------------
create or replace function public.gerar_novo_pin(p_trabalhador_id uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare v_pin text;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem gerar PIN'
      using errcode = 'insufficient_privilege';
  end if;
  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  update public.trabalhador
     set pin = v_pin
   where id = p_trabalhador_id
     and empresa_id = public.empresa_atual();
  if not found then
    raise exception 'colaborador não encontrado nesta empresa';
  end if;
  return v_pin;
end $$;

grant execute on function
  public.criar_colaborador(text, text, text, text, date, date, text, text, date),
  public.gerar_novo_pin(uuid)
  to authenticated;
