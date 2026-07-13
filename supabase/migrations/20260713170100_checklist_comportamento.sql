-- =====================================================================
-- 20260713170100_checklist_comportamento.sql — R2a: imutabilidade + RPCs
--
-- · Triggers de imutabilidade (padrão do trg_imutavel_picagem):
--     - versões 'publicada'/'arquivada' rejeitam UPDATE/DELETE
--       (única transição permitida: publicada -> arquivada, feita pela RPC);
--     - itens de versões não-rascunho rejeitam INSERT/UPDATE/DELETE
--       (publicar congela por trigger — decisão D1 do doc 13; o INSERT
--       também é bloqueado: acrescentar um item a uma versão publicada
--       mutaria conteúdo congelado);
--     - checklist_resposta e acao_corretiva: append-only após a
--       instância estar 'concluida' (UPDATE/DELETE rejeitados).
-- · RPCs SECURITY DEFINER (search_path '', escopo por empresa_id,
--   chamador tem de ser admin — padrão de corrigir_picagem):
--     - publicar_versao(uuid): valida (≥1 item; limites nunca menos
--       exigentes que o estatutário em limite_legal; frequencia_config
--       coerente com frequencia_tipo), arquiva a publicada anterior e
--       publica, atomicamente. Erros de validação são devolvidos TODOS
--       numa única exceção (relatório completo, nunca só o primeiro).
--     - criar_rascunho_de(uuid): clona versão + itens para um rascunho
--       novo; falha limpa se já existir rascunho do template.
--
-- NÃO incluída: instalar_templates_base() — o doc 04 (conteúdo HACCP:
-- os 7 templates e valores indicativos) não está no repo; semear
-- conteúdo de memória de modelo violaria a invariante 9. Divergência
-- registada em docs/R2a-notas.md; a RPC entra quando o doc 04 existir.
--
-- Regras de frequencia_config validadas no publicar (interpretação
-- registada em docs/R2a-notas.md — o agendador é R2c):
--   diaria    : vezes_por_dia int >= 1; janelas = array de 'HH:MM' com
--               comprimento igual a vezes_por_dia
--   por_turno : objeto sem chaves obrigatórias
--   semanal   : dia_semana int 1..7 (1 = segunda, ISO)
--   por_evento: objeto vazio (sem config)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Imutabilidade da versão
-- ---------------------------------------------------------------------
create or replace function public.bloquear_edicao_versao_checklist() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if tg_op = 'DELETE' then
    if old.estado in ('publicada','arquivada') then
      raise exception 'versão % é imutável (estado %): não pode ser apagada — crie um rascunho novo',
        old.numero, old.estado;
    end if;
    return old;  -- rascunho pode ser apagado (itens vão por cascade)
  end if;

  if old.estado = 'arquivada' then
    raise exception 'versão % arquivada é imutável', old.numero;
  end if;

  if old.estado = 'publicada' then
    -- única transição permitida: publicada -> arquivada, sem tocar em mais nada
    if new.estado <> 'arquivada'
       or new.id                is distinct from old.id
       or new.empresa_id        is distinct from old.empresa_id
       or new.template_id       is distinct from old.template_id
       or new.numero            is distinct from old.numero
       or new.frequencia_tipo   is distinct from old.frequencia_tipo
       or new.frequencia_config is distinct from old.frequencia_config
       or new.publicada_em      is distinct from old.publicada_em
       or new.created_at        is distinct from old.created_at then
      raise exception 'versão % publicada é imutável: só pode ser arquivada pela publicação de uma versão nova',
        old.numero;
    end if;
  end if;

  return new;
end
$function$;

drop trigger if exists trg_imutavel_versao_checklist on public.checklist_template_versao;
create trigger trg_imutavel_versao_checklist
  before update or delete on public.checklist_template_versao
  for each row execute function public.bloquear_edicao_versao_checklist();

-- ---------------------------------------------------------------------
-- 2. Imutabilidade dos itens de versões não-rascunho
-- ---------------------------------------------------------------------
create or replace function public.bloquear_edicao_item_checklist() returns trigger
language plpgsql set search_path to '' as $function$
declare
  v_estado text;
begin
  if tg_op in ('DELETE','UPDATE') then
    select estado into v_estado
      from public.checklist_template_versao where id = old.versao_id;
    -- v_estado null = versão a ser apagada em cascade (só rascunhos lá chegam)
    if v_estado is not null and v_estado <> 'rascunho' then
      raise exception 'item pertence a uma versão % (imutável): edite através de um rascunho novo', v_estado;
    end if;
  end if;

  if tg_op in ('INSERT','UPDATE') then
    select estado into v_estado
      from public.checklist_template_versao where id = new.versao_id;
    if v_estado is not null and v_estado <> 'rascunho' then
      raise exception 'não é possível acrescentar ou mover itens para uma versão % (imutável)', v_estado;
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$function$;

drop trigger if exists trg_imutavel_item_checklist on public.checklist_item;
create trigger trg_imutavel_item_checklist
  before insert or update or delete on public.checklist_item
  for each row execute function public.bloquear_edicao_item_checklist();

-- ---------------------------------------------------------------------
-- 3. Respostas e ações corretivas: append-only após instância concluída
-- ---------------------------------------------------------------------
create or replace function public.bloquear_edicao_resposta_checklist() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if exists (
    select 1 from public.checklist_instancia i
     where i.id = old.instancia_id and i.estado = 'concluida'
  ) then
    raise exception 'prova HACCP imutável: a instância está concluída — respostas não são editáveis nem apagáveis';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$function$;

drop trigger if exists trg_imutavel_resposta_checklist on public.checklist_resposta;
create trigger trg_imutavel_resposta_checklist
  before update or delete on public.checklist_resposta
  for each row execute function public.bloquear_edicao_resposta_checklist();

create or replace function public.bloquear_edicao_acao_corretiva() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if exists (
    select 1
      from public.checklist_resposta r
      join public.checklist_instancia i on i.id = r.instancia_id
     where r.id = old.resposta_id and i.estado = 'concluida'
  ) then
    raise exception 'prova HACCP imutável: a instância está concluída — ações corretivas não são editáveis nem apagáveis';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$function$;

drop trigger if exists trg_imutavel_acao_corretiva on public.acao_corretiva;
create trigger trg_imutavel_acao_corretiva
  before update or delete on public.acao_corretiva
  for each row execute function public.bloquear_edicao_acao_corretiva();

-- ---------------------------------------------------------------------
-- 4. publicar_versao — validação completa + publicação atómica
-- ---------------------------------------------------------------------
create or replace function public.publicar_versao(p_versao_id uuid)
returns json
language plpgsql security definer set search_path to '' as $function$
declare
  v_emp   uuid := public.empresa_atual();
  v       record;
  it      record;
  erros   text[] := '{}';
  v_n_itens          int;
  v_vezes            numeric;
  v_n_janelas        int;
  v_janela           text;
  v_dia              numeric;
  v_arquivada_numero int;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem publicar versões'
      using errcode = 'insufficient_privilege';
  end if;
  if v_emp is null then
    raise exception 'sessão sem empresa' using errcode = 'insufficient_privilege';
  end if;

  select * into v
    from public.checklist_template_versao
   where id = p_versao_id and empresa_id = v_emp
   for update;
  if not found then
    raise exception 'versão não encontrada nesta empresa';
  end if;
  if v.estado <> 'rascunho' then
    raise exception 'só um rascunho pode ser publicado (estado atual: %)', v.estado;
  end if;

  -- (a) pelo menos um item
  select count(*) into v_n_itens
    from public.checklist_item
   where versao_id = v.id and empresa_id = v_emp;
  if v_n_itens = 0 then
    erros := erros || 'a versão não tem itens — um checklist vazio não é publicável'::text;
  end if;

  -- (b) frequencia_config coerente com frequencia_tipo
  if jsonb_typeof(v.frequencia_config) is distinct from 'object' then
    erros := erros || 'frequencia_config tem de ser um objeto JSON'::text;
  else
    case v.frequencia_tipo
      when 'diaria' then
        if jsonb_typeof(v.frequencia_config->'vezes_por_dia') is distinct from 'number' then
          erros := erros || 'frequência diária exige "vezes_por_dia" numérico'::text;
        else
          v_vezes := (v.frequencia_config->>'vezes_por_dia')::numeric;
          if v_vezes < 1 or v_vezes <> trunc(v_vezes) then
            erros := erros || format('"vezes_por_dia" tem de ser inteiro >= 1 (recebido: %s)', v_vezes);
          end if;
        end if;
        if jsonb_typeof(v.frequencia_config->'janelas') is distinct from 'array' then
          erros := erros || 'frequência diária exige "janelas" (array de horas "HH:MM")'::text;
        else
          v_n_janelas := jsonb_array_length(v.frequencia_config->'janelas');
          if v_vezes is not null and v_n_janelas <> v_vezes then
            erros := erros || format('número de janelas (%s) difere de vezes_por_dia (%s)', v_n_janelas, v_vezes);
          end if;
          for v_janela in
            select jsonb_array_elements_text(v.frequencia_config->'janelas')
          loop
            if v_janela !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
              erros := erros || format('janela "%s" não é uma hora válida "HH:MM"', v_janela);
            end if;
          end loop;
        end if;
      when 'semanal' then
        if jsonb_typeof(v.frequencia_config->'dia_semana') is distinct from 'number' then
          erros := erros || 'frequência semanal exige "dia_semana" (1=segunda .. 7=domingo)'::text;
        else
          v_dia := (v.frequencia_config->>'dia_semana')::numeric;
          if v_dia < 1 or v_dia > 7 or v_dia <> trunc(v_dia) then
            erros := erros || format('"dia_semana" tem de ser inteiro entre 1 e 7 (recebido: %s)', v_dia);
          end if;
        end if;
      when 'por_evento' then
        if v.frequencia_config <> '{}'::jsonb then
          erros := erros || 'frequência por_evento não leva configuração (config tem de ser vazia)'::text;
        end if;
      else
        null;  -- por_turno: sem chaves obrigatórias
    end case;
  end if;

  -- (c) itens: booleano coerente; ligação a limite_legal nunca menos exigente
  for it in
    select i.*, l.controlo    as legal_controlo,
                l.unidade     as legal_unidade,
                l.limite_min  as legal_min,
                l.limite_max  as legal_max,
                l.norma       as legal_norma
      from public.checklist_item i
      left join public.limite_legal l on l.id = i.limite_legal_id
     where i.versao_id = v.id and i.empresa_id = v_emp
     order by i.ordem
  loop
    if it.tipo_resposta = 'booleano' and it.booleano_conforme is null then
      erros := erros || format('item %s ("%s"): booleano sem booleano_conforme definido', it.ordem, it.texto);
    end if;

    if it.limite_legal_id is not null then
      if it.tipo_resposta <> 'numerico' then
        erros := erros || format('item %s ("%s"): ligado a limite legal mas não é numérico', it.ordem, it.texto);
      else
        if it.unidade is distinct from it.legal_unidade then
          erros := erros || format('item %s ("%s"): unidade "%s" difere da unidade estatutária "%s" (%s)',
            it.ordem, it.texto, coalesce(it.unidade, '—'), it.legal_unidade, it.legal_norma);
        end if;
        if it.legal_max is not null and (it.limite_max is null or it.limite_max > it.legal_max) then
          erros := erros || format('item %s ("%s"): limite máximo %s é menos exigente que o estatutário %s %s (%s)',
            it.ordem, it.texto, coalesce(it.limite_max::text, 'inexistente'),
            it.legal_max, it.legal_unidade, it.legal_norma);
        end if;
        if it.legal_min is not null and (it.limite_min is null or it.limite_min < it.legal_min) then
          erros := erros || format('item %s ("%s"): limite mínimo %s é menos exigente que o estatutário %s %s (%s)',
            it.ordem, it.texto, coalesce(it.limite_min::text, 'inexistente'),
            it.legal_min, it.legal_unidade, it.legal_norma);
        end if;
      end if;
    end if;
  end loop;

  if array_length(erros, 1) > 0 then
    raise exception E'publicação inválida:\n- %', array_to_string(erros, E'\n- ');
  end if;

  -- arquivar a publicada anterior (transição permitida pelo trigger)
  update public.checklist_template_versao
     set estado = 'arquivada'
   where template_id = v.template_id and empresa_id = v_emp and estado = 'publicada'
  returning numero into v_arquivada_numero;

  update public.checklist_template_versao
     set estado = 'publicada', publicada_em = now()
   where id = v.id and empresa_id = v_emp;

  return json_build_object(
    'versao_id', v.id,
    'template_id', v.template_id,
    'numero', v.numero,
    'itens', v_n_itens,
    'versao_arquivada', v_arquivada_numero
  );
end
$function$;

revoke all on function public.publicar_versao(uuid) from public;
grant execute on function public.publicar_versao(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. criar_rascunho_de — clona versão + itens para um rascunho novo
-- ---------------------------------------------------------------------
create or replace function public.criar_rascunho_de(p_versao_id uuid)
returns json
language plpgsql security definer set search_path to '' as $function$
declare
  v_emp    uuid := public.empresa_atual();
  v        record;
  v_novo   uuid;
  v_numero int;
  v_itens  int;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem criar rascunhos'
      using errcode = 'insufficient_privilege';
  end if;
  if v_emp is null then
    raise exception 'sessão sem empresa' using errcode = 'insufficient_privilege';
  end if;

  select * into v
    from public.checklist_template_versao
   where id = p_versao_id and empresa_id = v_emp;
  if not found then
    raise exception 'versão não encontrada nesta empresa';
  end if;

  if exists (
    select 1 from public.checklist_template_versao
     where template_id = v.template_id and empresa_id = v_emp and estado = 'rascunho'
  ) then
    raise exception 'já existe um rascunho deste template — edite-o ou apague-o antes de criar outro';
  end if;

  select coalesce(max(numero), 0) + 1 into v_numero
    from public.checklist_template_versao
   where template_id = v.template_id and empresa_id = v_emp;

  insert into public.checklist_template_versao
    (empresa_id, template_id, numero, estado, frequencia_tipo, frequencia_config)
  values
    (v_emp, v.template_id, v_numero, 'rascunho', v.frequencia_tipo, v.frequencia_config)
  returning id into v_novo;

  insert into public.checklist_item
    (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
     limite_min, limite_max, booleano_conforme, obrigatorio,
     limite_fonte, limite_referencia, limite_legal_id)
  select empresa_id, v_novo, ordem, texto, tipo_resposta, unidade,
         limite_min, limite_max, booleano_conforme, obrigatorio,
         limite_fonte, limite_referencia, limite_legal_id
    from public.checklist_item
   where versao_id = v.id and empresa_id = v_emp;
  get diagnostics v_itens = row_count;

  return json_build_object(
    'versao_id', v_novo,
    'template_id', v.template_id,
    'numero', v_numero,
    'itens_clonados', v_itens
  );
end
$function$;

revoke all on function public.criar_rascunho_de(uuid) from public;
grant execute on function public.criar_rascunho_de(uuid) to authenticated;
