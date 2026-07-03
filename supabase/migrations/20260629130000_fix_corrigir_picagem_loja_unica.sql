-- 20260629130000_fix_corrigir_picagem_loja_unica.sql
-- Bug: corrigir_picagem, no ramo de fallback "sem histórico", usava
--   select count(*), min(id) into v_n, v_loja from public.loja ...
-- mas NÃO existe agregado min(uuid) no Postgres -> "function min(uuid) does not exist".
-- Só disparava para colaboradores SEM nenhuma picagem (a loja deixava de se resolver pela
-- última picagem e caía neste ramo). Resultado: toda a inserção manual para um colaborador
-- novo falhava (folha de horas e, por arrasto, corrigir_picagem_bloco, que reutiliza esta RPC).
--
-- Correção: contar e, só se houver exatamente uma loja ativa, selecioná-la diretamente
-- (sem agregar uuid). Resto da função idêntico ao original.

drop function if exists public.corrigir_picagem(uuid, text, timestamptz, text, uuid);

create function public.corrigir_picagem(
  p_trabalhador_id uuid,
  p_tipo text,
  p_momento timestamptz,
  p_motivo text default null,
  p_loja_id uuid default null
) returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_emp uuid := public.empresa_atual();
  v_loja uuid; v_n int;
  v_vid uuid := gen_random_uuid(); v_pid uuid;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode='insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento is null then raise exception 'momento em falta'; end if;
  if not exists (select 1 from public.trabalhador where id=p_trabalhador_id and empresa_id=v_emp) then
    raise exception 'trabalhador não encontrado nesta empresa';
  end if;

  -- Resolver a loja: param -> última picagem do trabalhador -> única loja ativa.
  v_loja := p_loja_id;
  if v_loja is not null and not exists (select 1 from public.loja where id=v_loja and empresa_id=v_emp) then
    raise exception 'loja não pertence à empresa';
  end if;
  if v_loja is null then
    select v.loja_id into v_loja
      from public.picagem p
      join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
     where v.empresa_id=v_emp and v.trabalhador_id=p_trabalhador_id
     order by v.momento_dispositivo desc limit 1;
  end if;
  if v_loja is null then
    -- FIX: sem min(uuid). Conta e, se houver exatamente uma loja ativa, escolhe-a.
    select count(*) into v_n from public.loja where empresa_id=v_emp and ativa=true;
    if v_n = 1 then
      select id into v_loja from public.loja where empresa_id=v_emp and ativa=true;
    end if;
  end if;
  if v_loja is null then raise exception 'indique a loja da correção'; end if;

  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, momento_servidor,
     foto_url, chave_idempotencia, autorizacao_offline, correcao_manual, criada_por)
  values
    (v_vid, v_emp, p_trabalhador_id, v_loja, p_momento, now(),
     null, gen_random_uuid(), false, true, auth.uid());

  insert into public.picagem (empresa_id, verificacao_id, tipo)
  values (v_emp, v_vid, p_tipo) returning id into v_pid;

  return json_build_object('picagem_id', v_pid, 'verificacao_id', v_vid, 'loja_id', v_loja);
end
$function$;

revoke all on function public.corrigir_picagem(uuid, text, timestamptz, text, uuid)
  from public, anon, authenticated;
grant execute on function public.corrigir_picagem(uuid, text, timestamptz, text, uuid)
  to authenticated;
