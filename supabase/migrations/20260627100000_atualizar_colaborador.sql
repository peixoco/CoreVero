-- RPC atómica para editar um colaborador (identificação/contrato).
-- Atualiza trabalhador (nome, area) + UPSERT em trabalhador_detalhe.
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
security invoker
set search_path = ''
as $$
declare v_empresa uuid := public.empresa_atual();
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem editar colaboradores'
      using errcode = 'insufficient_privilege';
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

grant execute on function
  public.atualizar_colaborador(uuid, text, text, text, date, text, date, date, text, text)
  to authenticated;