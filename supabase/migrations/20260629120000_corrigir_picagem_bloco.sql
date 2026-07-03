-- 20260629120000_corrigir_picagem_bloco.sql
-- Frente A — Picagens em Bloco
--
-- Aplica, numa transação, picagens manuais a N datas × N trabalhadores × M (tipo,hora),
-- reutilizando public.corrigir_picagem (autoria do admin via criada_por, correcao_manual=true,
-- imutabilidade por anulação). NÃO é um caminho de escrita paralelo — é um ciclo sobre a RPC
-- unitária já existente, para herdar a mesma resolução de loja e as mesmas garantias.
--
-- Pré-flight de sequência por TRABALHADOR-DIA: funde as picagens existentes (não anuladas) com
-- as novas, ordena por momento e percorre a MESMA tabela de transições de public.sequencia_valida.
-- Um trabalhador-dia cuja sequência fique inválida é IGNORADO e reportado em `ignoradas` — não
-- aplica nenhuma das suas linhas (nada parte em silêncio; nada se cria errado).
--
-- p_simular = true NÃO escreve: devolve o plano (planeadas / ignoradas / erros / detalhes).
-- p_simular = false aplica e devolve o realizado (aplicadas / ignoradas / erros / detalhes).
--
-- Nota de desenho: o pré-flight revalida também as picagens já existentes do dia. Se o dia já
-- estiver com sequência partida (corrupção anterior), o bloco para esse dia é recusado — por
-- desenho (não empilhar sobre um dia já inconsistente). O passo que falha vai no motivo.
--
-- Limitação conhecida (latente na Frente A, NÃO corrigida aqui): public.sequencia_valida não
-- exclui picagens anuladas ao procurar a anterior. Este pré-flight EXCLUI anuladas (correto).
-- Fechar a divergência em sequencia_valida é um item à parte.

drop function if exists public.corrigir_picagem_bloco(date[], uuid[], jsonb, uuid, boolean);

create function public.corrigir_picagem_bloco(
  p_datas         date[],
  p_trabalhadores uuid[],
  p_movimentos    jsonb,                 -- [{"tipo":"entrada","hora":"09:00"}, {"tipo":"saida","hora":"18:00"}]
  p_loja_id       uuid    default null,  -- opcional: aplica a todos; se null, resolve por trabalhador
  p_simular       boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_emp       uuid := public.empresa_atual();
  v_trab      uuid;
  v_data      date;
  v_mov       jsonb;
  v_tipo      text;
  v_hora      text;
  v_momento   timestamptz;
  v_momentos  timestamptz[];
  v_tipos     text[];
  v_prev      text;
  v_cur       text;
  v_ok        boolean;
  v_passo     text;
  v_planeadas int := 0;
  v_aplicadas int := 0;
  v_ignoradas jsonb := '[]'::jsonb;
  v_erros     jsonb := '[]'::jsonb;
  v_det       jsonb := '[]'::jsonb;
  v_nome      text;
  v_i         int;
  r           record;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode = 'insufficient_privilege';
  end if;

  if p_datas is null or array_length(p_datas, 1) is null then
    raise exception 'indique pelo menos uma data';
  end if;
  if p_trabalhadores is null or array_length(p_trabalhadores, 1) is null then
    raise exception 'indique pelo menos um colaborador';
  end if;
  if p_movimentos is null or jsonb_array_length(p_movimentos) = 0 then
    raise exception 'indique pelo menos um movimento';
  end if;

  -- Validar movimentos (tipo + formato de hora) uma só vez, antes de qualquer escrita.
  for v_mov in select * from jsonb_array_elements(p_movimentos) loop
    v_tipo := v_mov->>'tipo';
    v_hora := trim(coalesce(v_mov->>'hora', ''));
    if v_tipo not in ('entrada', 'saida', 'inicio_intervalo', 'fim_intervalo') then
      raise exception 'tipo de movimento inválido: %', coalesce(v_tipo, '(vazio)');
    end if;
    if v_hora !~ '^\d{2}:\d{2}$' then
      raise exception 'hora inválida (use HH:MM): %', coalesce(v_hora, '(vazio)');
    end if;
  end loop;

  -- Loja opcional: se indicada, tem de pertencer à empresa. Se null, corrigir_picagem resolve
  -- por trabalhador (última picagem -> única loja ativa).
  if p_loja_id is not null and not exists (
    select 1 from public.loja where id = p_loja_id and empresa_id = v_emp
  ) then
    raise exception 'loja não pertence à empresa';
  end if;

  foreach v_trab in array p_trabalhadores loop
    select nome into v_nome
      from public.trabalhador
     where id = v_trab and empresa_id = v_emp;

    if v_nome is null then
      v_erros := v_erros || jsonb_build_object(
        'trabalhador', v_trab,
        'erro', 'colaborador não encontrado nesta empresa');
      continue;
    end if;

    foreach v_data in array p_datas loop
      begin
        -- Construir os eventos novos deste trabalhador-dia.
        v_momentos := array[]::timestamptz[];
        v_tipos    := array[]::text[];
        for v_mov in select * from jsonb_array_elements(p_movimentos) loop
          v_tipo    := v_mov->>'tipo';
          v_hora    := trim(v_mov->>'hora');
          v_momento := (v_data::text || ' ' || v_hora)::timestamp at time zone 'Europe/Lisbon';
          v_momentos := v_momentos || v_momento;
          v_tipos    := v_tipos || v_tipo;
        end loop;

        -- PRÉ-FLIGHT: funde existentes (não anuladas) + novos, ordena por momento,
        -- percorre a tabela de transições (igual a sequencia_valida).
        v_prev := null;
        v_ok   := true;
        v_passo := null;
        for r in
          select tt from (
            select v.momento_dispositivo as mm, p.tipo as tt
              from public.picagem p
              join public.verificacao v
                on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
             where v.empresa_id = v_emp
               and v.trabalhador_id = v_trab
               and not p.anulada
               and (v.momento_dispositivo at time zone 'Europe/Lisbon')::date = v_data
            union all
            select mm, tt from unnest(v_momentos, v_tipos) as u(mm, tt)
          ) s
          order by mm
        loop
          v_cur := r.tt;
          v_ok := case
            when v_prev is null                          then v_cur = 'entrada'
            when v_prev in ('entrada', 'fim_intervalo')  then v_cur in ('saida', 'inicio_intervalo')
            when v_prev = 'inicio_intervalo'             then v_cur = 'fim_intervalo'
            when v_prev = 'saida'                        then v_cur = 'entrada'
            else false
          end;
          if not v_ok then
            v_passo := coalesce(v_prev, '(início do dia)') || ' → ' || v_cur;
            exit;
          end if;
          v_prev := v_cur;
        end loop;

        if not v_ok then
          v_ignoradas := v_ignoradas || jsonb_build_object(
            'trabalhador', v_trab,
            'nome', v_nome,
            'data', v_data::text,
            'motivo', 'sequência inválida no dia (' || v_passo || ')');
          continue;
        end if;

        -- Aplicar (ou apenas contar, em simulação) por ordem de momento.
        for v_i in 1 .. array_length(v_momentos, 1) loop
          v_planeadas := v_planeadas + 1;
          v_det := v_det || jsonb_build_object(
            'trabalhador', v_trab,
            'nome', v_nome,
            'data', v_data::text,
            'tipo', v_tipos[v_i],
            'hora', to_char(v_momentos[v_i] at time zone 'Europe/Lisbon', 'HH24:MI'));
          if not p_simular then
            perform public.corrigir_picagem(v_trab, v_tipos[v_i], v_momentos[v_i], 'bloco', p_loja_id);
            v_aplicadas := v_aplicadas + 1;
          end if;
        end loop;

      exception when others then
        v_erros := v_erros || jsonb_build_object(
          'trabalhador', v_trab,
          'nome', v_nome,
          'data', v_data::text,
          'erro', sqlerrm);
      end;
    end loop;
  end loop;

  return jsonb_build_object(
    'simulado',  p_simular,
    'planeadas', v_planeadas,
    'aplicadas', v_aplicadas,
    'ignoradas', v_ignoradas,
    'erros',     v_erros,
    'detalhes',  v_det
  );
end
$function$;

revoke all on function public.corrigir_picagem_bloco(date[], uuid[], jsonb, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.corrigir_picagem_bloco(date[], uuid[], jsonb, uuid, boolean)
  to authenticated;
