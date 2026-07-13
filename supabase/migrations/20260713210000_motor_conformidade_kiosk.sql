-- =====================================================================
-- 20260713210000_motor_conformidade_kiosk.sql — R2b: motor de conformidade
--   HACCP e RPCs do kiosk (doc 13 §3)
--
-- Porquê: fecha o ciclo de preenchimento no kiosk. O R2a criou o schema
-- e o construtor de templates (admin); o R2b acrescenta:
--   (1) a lógica de avaliação de conformidade no servidor (D3 do doc 13);
--   (2) a RPC de leitura para o kiosk obter templates aplicáveis;
--   (3) a RPC de escrita atómica: valida, insere verificacao + instância +
--       respostas (conforme avaliado pelo servidor) + ações corretivas +
--       notificações de não conformidade, tudo na mesma transação.
--
-- Invariantes respeitadas:
--   · 3: todas as funções SECURITY DEFINER têm set search_path to '' e
--     escopam TODAS as queries por empresa_id.
--   · 6: revoke/grant explícitos em todas as funções novas.
--   · D3 (doc 13): o kiosk NUNCA envia conforme — o servidor avalia sempre.
--   · Triggers de imutabilidade do R2a (trg_imutavel_resposta_checklist,
--     trg_imutavel_acao_corretiva) só disparam em UPDATE/DELETE, não
--     em INSERT; a instância é criada como 'concluida' e os INSERTs de
--     resposta e ação seguem — a ordem é correta.
--
-- Divergências face à especificação (registadas aqui para revisão humana):
--   · notificacao.destinatario é nullable na BD (tabela criada em
--     20260625090000; sem campo not null e sem fonte configurável por
--     loja no R2b). Inserção com destinatario = null — o worker R2c
--     irá resolver o destino via configuração da loja.
--   · a verificacao segue o contrato de foto de atribuição da picagem
--     (registar_picagem): o servidor gera o id, constrói o caminho
--     {empresa}/{loja}/{trabalhador}/{id}.jpg, grava-o em foto_url e
--     devolve foto_path para o kiosk fazer o upload (a policy do bucket
--     picagens já cobre este caminho). A prova no admin inclui a foto
--     de atribuição enquanto viva (doc 13 §5, gate do R2b).
--   · sem chave_idempotencia nesta fase (coluna nullable): rede instável
--     pode duplicar um preenchimento on-demand; idempotência entra no
--     R2c com o agendador (nota do revisor-sql).
-- =====================================================================

-- =====================================================================
-- 1. avaliar_conformidade — função pura interna (sem acesso a tabelas)
--    Avalia uma resposta de checklist contra o item tipado (4 braços do
--    doc 13 §3). IMMUTABLE: só opera sobre os argumentos recebidos.
--    SEM security definer: é chamada internamente pelas RPCs definer.
-- =====================================================================
create or replace function public.avaliar_conformidade(
  p_item     public.checklist_item,
  p_valor    text,
  p_foto_url text default null
)
returns table (conforme boolean, motivo text)
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_num  numeric;
  v_bool boolean;
begin
  case p_item.tipo_resposta

    when 'numerico' then
      -- NULL, vazio ou não-numérico → ilegível
      if p_valor is null or trim(p_valor) = '' then
        conforme := false;
        motivo   := 'valor ilegível';
        return next; return;
      end if;
      begin
        v_num := p_valor::numeric;
      exception when others then
        conforme := false;
        motivo   := 'valor ilegível';
        return next; return;
      end;
      -- conforme ⇔ dentro dos limites (null = sem limite)
      if (p_item.limite_min is null or v_num >= p_item.limite_min)
         and (p_item.limite_max is null or v_num <= p_item.limite_max) then
        conforme := true;
        motivo   := null;
        return next; return;
      end if;
      -- não conforme: identifica o limite violado
      if p_item.limite_max is not null and v_num > p_item.limite_max then
        conforme := false;
        motivo   := format('valor %s acima do limite máximo %s', v_num, p_item.limite_max);
      else
        conforme := false;
        motivo   := format('valor %s abaixo do limite mínimo %s', v_num, p_item.limite_min);
      end if;
      return next; return;

    when 'booleano' then
      -- NULL, vazio ou não-booleano → ilegível
      if p_valor is null or trim(p_valor) = '' then
        conforme := false;
        motivo   := 'valor ilegível';
        return next; return;
      end if;
      begin
        v_bool := p_valor::boolean;
      exception when others then
        conforme := false;
        motivo   := 'valor ilegível';
        return next; return;
      end;
      -- conforme ⇔ valor corresponde ao booleano_conforme (default true)
      if v_bool = coalesce(p_item.booleano_conforme, true) then
        conforme := true;
        motivo   := null;
        return next; return;
      end if;
      conforme := false;
      motivo   := format('resposta "%s" não conforme (esperado: %s)',
                         p_valor, coalesce(p_item.booleano_conforme, true));
      return next; return;

    when 'texto' then
      -- conforme ⇔ se obrigatório então valor não nulo e não vazio
      if p_item.obrigatorio and (p_valor is null or trim(p_valor) = '') then
        conforme := false;
        motivo   := 'resposta obrigatória em falta';
        return next; return;
      end if;
      conforme := true;
      motivo   := null;
      return next; return;

    when 'foto' then
      -- conforme ⇔ foto_url presente e não vazia
      if p_foto_url is null or trim(p_foto_url) = '' then
        conforme := false;
        motivo   := 'fotografia obrigatória em falta';
        return next; return;
      end if;
      conforme := true;
      motivo   := null;
      return next; return;

    else
      raise exception 'tipo_resposta desconhecido: %', p_item.tipo_resposta;

  end case;
end
$function$;

-- interna: nenhum role de cliente executa diretamente
revoke all on function public.avaliar_conformidade(public.checklist_item, text, text)
  from public, anon, authenticated;

-- =====================================================================
-- 2. obter_checklists_kiosk — leitura de templates aplicáveis à loja
--    SECURITY DEFINER (ignora RLS; escopo manual por empresa_id + loja).
--    O kiosk NUNCA faz SELECT direto nas tabelas checklist_*.
-- =====================================================================
create or replace function public.obter_checklists_kiosk()
returns json
language plpgsql
security definer
stable
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_result  json;
begin
  -- guards do kiosk (mesmo padrão de iniciar_picagem)
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode carregar checklists'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;

  -- templates ativos da empresa com versão publicada, aplicáveis à loja
  select json_agg(
    json_build_object(
      'template_id',     t.id,
      'nome',            t.nome,
      'versao_id',       v.id,
      'numero',          v.numero,
      'frequencia_tipo', v.frequencia_tipo,
      'itens', (
        select json_agg(
          json_build_object(
            'id',                i.id,
            'ordem',             i.ordem,
            'texto',             i.texto,
            'tipo_resposta',     i.tipo_resposta,
            'unidade',           i.unidade,
            'limite_min',        i.limite_min,
            'limite_max',        i.limite_max,
            'booleano_conforme', i.booleano_conforme,
            'obrigatorio',       i.obrigatorio
          ) order by i.ordem
        )
        from public.checklist_item i
        where i.versao_id   = v.id
          and i.empresa_id  = v_empresa
      )
    )
  )
  into v_result
  from public.checklist_template t
  join public.checklist_template_versao v
    on v.template_id = t.id
   and v.empresa_id  = v_empresa
   and v.estado      = 'publicada'
  where t.empresa_id = v_empresa
    and t.ativo
    and (t.loja_id is null or t.loja_id = v_loja);

  return coalesce(v_result, '[]'::json);
end
$function$;

revoke all on function public.obter_checklists_kiosk() from public, anon;
grant execute on function public.obter_checklists_kiosk() to authenticated;

-- =====================================================================
-- 3. registar_checklist — RPC atómica de preenchimento de checklist
--    SECURITY DEFINER, uma função = uma transação.
--
-- p_respostas: jsonb — array de {"item_id": uuid, "valor": text|null,
--              "foto_url": text|null}. Campo "conforme" do cliente
--              é IGNORADO — o servidor avalia sempre.
-- p_acoes:     jsonb — array de {"item_id": uuid, "descricao": text}.
--
-- Passos (doc 13 §3):
--   1. Guards do kiosk.
--   2. Validação de PIN server-side.
--   3. Validação de p_momento_dispositivo.
--   4. Validação da versão (existe, publicada, template ativo, loja ok).
--   5. Validações acumuladas (erros[]):
--      · item_id de p_respostas pertence à versão;
--      · item_id duplicado em p_respostas;
--      · itens obrigatórios têm resposta;
--      · conformidade de cada resposta via avaliar_conformidade;
--      · toda a resposta não conforme tem ação com descrição não vazia;
--      · ações sem resposta não conforme correspondente (órfãs).
--      → raise com relatório completo se erros > 0.
--   6. Insere verificacao (sem foto_url, sem chave_idempotencia — ver nota
--      de divergência no cabeçalho).
--   7. Insere checklist_instancia (estado='concluida', due_at=null).
--   8. Insere checklist_resposta por item (conforme do SERVIDOR).
--   9. Insere acao_corretiva por cada entrada de p_acoes válida.
--  10. Insere notificacao por resposta não conforme (destinatario=null;
--      ver divergência no cabeçalho).
--  11. Devolve json com resumo.
-- =====================================================================
create or replace function public.registar_checklist(
  p_codigo_pessoal      text,
  p_pin                 text,
  p_versao_id           uuid,
  p_momento_dispositivo timestamptz,
  p_respostas           jsonb,
  p_acoes               jsonb
)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa         uuid := public.empresa_atual();
  v_loja            uuid := public.loja_atual();
  v_trabalhador_id  uuid;
  v_versao          record;
  v_verificacao_id  uuid := gen_random_uuid();
  v_foto_path       text;
  v_instancia_id    uuid;
  v_resposta_id     uuid;

  -- validação acumulada (padrão publicar_versao)
  erros             text[] := '{}';

  -- iteração sobre respostas
  rec_resp          record;
  v_resp_item_id    uuid;
  v_resp_valor      text;
  v_resp_foto       text;
  v_resp_item       public.checklist_item;
  v_resp_item_ids   uuid[] := '{}';   -- item_ids presentes em p_respostas

  -- avaliação de conformidade
  v_conforme        boolean;
  v_motivo          text;

  -- rastreio de não conformes (arrays paralelos)
  v_nc_item_ids     uuid[] := '{}';
  v_nc_motivos      text[] := '{}';

  -- iteração sobre ações
  rec_acao          record;
  v_acao_item_id    uuid;
  v_acao_descricao  text;
  v_acao_item_ids   uuid[] := '{}';   -- item_ids de ações válidas (nc + desc non-empty)

  -- contadores para o resumo devolvido
  v_n_respostas     int := 0;
  v_n_nao_conformes int := 0;
  v_n_acoes         int := 0;

  -- índice para loop sobre array de não conformes
  v_nc_idx          int;
  v_nc_count        int;
begin

  -- ----------------------------------------------------------------
  -- 1. Guards do kiosk (mesmo padrão de iniciar_picagem)
  -- ----------------------------------------------------------------
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar checklists'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;

  -- ----------------------------------------------------------------
  -- 2. Validação de PIN server-side (mesmo padrão de iniciar_picagem)
  -- ----------------------------------------------------------------
  select t.id into v_trabalhador_id
    from public.trabalhador t
   where t.empresa_id     = v_empresa
     and t.codigo_pessoal = p_codigo_pessoal
     and t.ativo          = true
     and t.pin is not null
     and t.pin            = p_pin;

  if v_trabalhador_id is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  -- ----------------------------------------------------------------
  -- 3. Validação de p_momento_dispositivo
  -- ----------------------------------------------------------------
  if p_momento_dispositivo is null then
    raise exception 'momento do dispositivo em falta';
  end if;

  -- ----------------------------------------------------------------
  -- 4. Validação da versão (pré-condições: raise imediato)
  -- ----------------------------------------------------------------
  select v.id,
         v.template_id,
         v.numero,
         v.frequencia_tipo,
         v.estado,
         t.ativo   as template_ativo,
         t.loja_id as template_loja_id
    into v_versao
    from public.checklist_template_versao v
    join public.checklist_template t
      on t.id         = v.template_id
     and t.empresa_id = v_empresa
   where v.id         = p_versao_id
     and v.empresa_id = v_empresa;

  if not found then
    raise exception 'versão % não encontrada nesta empresa', p_versao_id;
  end if;
  if v_versao.estado <> 'publicada' then
    raise exception 'versão % não está publicada (estado: %)', p_versao_id, v_versao.estado;
  end if;
  if not v_versao.template_ativo then
    raise exception 'template da versão % está inativo', p_versao_id;
  end if;
  if v_versao.template_loja_id is not null and v_versao.template_loja_id <> v_loja then
    raise exception 'template da versão % não é aplicável a esta loja', p_versao_id;
  end if;

  -- ----------------------------------------------------------------
  -- 5. Validações acumuladas (TODAS antes do raise)
  -- ----------------------------------------------------------------

  -- 5a. Para cada item_id em p_respostas: duplicados e pertença à versão
  for rec_resp in
    select value as elem
      from jsonb_array_elements(coalesce(p_respostas, '[]'::jsonb))
  loop
    v_resp_item_id := (rec_resp.elem->>'item_id')::uuid;

    -- duplicado
    if v_resp_item_id = any(v_resp_item_ids) then
      erros := erros || format('item_id duplicado em p_respostas: %s', v_resp_item_id);
      continue;
    end if;
    v_resp_item_ids := v_resp_item_ids || v_resp_item_id;

    -- pertença à versão
    select * into v_resp_item
      from public.checklist_item
     where id         = v_resp_item_id
       and versao_id  = p_versao_id
       and empresa_id = v_empresa;

    if not found then
      erros := erros || format('item %s não pertence à versão %s', v_resp_item_id, p_versao_id);
      continue;  -- sem item_row, não é possível avaliar conformidade
    end if;

    -- 5d. Avaliar conformidade (autoridade do servidor)
    v_resp_valor := rec_resp.elem->>'valor';
    v_resp_foto  := rec_resp.elem->>'foto_url';

    select ac.conforme, ac.motivo
      into v_conforme, v_motivo
      from public.avaliar_conformidade(v_resp_item, v_resp_valor, v_resp_foto) ac;

    if not v_conforme then
      v_nc_item_ids := v_nc_item_ids || v_resp_item_id;
      v_nc_motivos  := v_nc_motivos  || coalesce(v_motivo, 'não conforme');
    end if;
  end loop;

  -- 5b. Itens obrigatórios com resposta em falta
  for v_resp_item in
    select * from public.checklist_item
     where versao_id  = p_versao_id
       and empresa_id = v_empresa
       and obrigatorio = true
  loop
    if not (v_resp_item.id = any(v_resp_item_ids)) then
      erros := erros || format('resposta obrigatória em falta para o item "%s"', v_resp_item.texto);
    end if;
  end loop;

  -- 5e/5f. Validar ações: órfãs e descrição vazia; construir v_acao_item_ids
  for rec_acao in
    select value as elem
      from jsonb_array_elements(coalesce(p_acoes, '[]'::jsonb))
  loop
    v_acao_item_id   := (rec_acao.elem->>'item_id')::uuid;
    v_acao_descricao := rec_acao.elem->>'descricao';

    if not (v_acao_item_id = any(v_nc_item_ids)) then
      -- ação órfã: item_id sem resposta não conforme correspondente
      erros := erros || format(
        'ação corretiva órfã: item %s não tem resposta não conforme', v_acao_item_id);
    elsif v_acao_descricao is null or trim(v_acao_descricao) = '' then
      -- ação com descrição vazia
      erros := erros || format(
        'ação corretiva para item %s tem descrição vazia', v_acao_item_id);
    elsif v_acao_item_id = any(v_acao_item_ids) then
      -- duplicada: duas ações para o mesmo item não conforme
      erros := erros || format(
        'ação corretiva duplicada para o item %s', v_acao_item_id);
    else
      -- ação válida: regista o item_id (para o check 5e do nc → ação)
      v_acao_item_ids := v_acao_item_ids || v_acao_item_id;
    end if;
  end loop;

  -- 5e. REGRA DURA: toda a resposta não conforme tem de ter ação
  v_nc_count := coalesce(array_length(v_nc_item_ids, 1), 0);
  for v_nc_idx in 1..v_nc_count loop
    if not (v_nc_item_ids[v_nc_idx] = any(v_acao_item_ids)) then
      erros := erros || format(
        'resposta não conforme no item "%s" (motivo: %s) requer uma ação corretiva',
        (select texto from public.checklist_item
          where id = v_nc_item_ids[v_nc_idx] and empresa_id = v_empresa),
        v_nc_motivos[v_nc_idx]
      );
    end if;
  end loop;

  -- relatório completo de erros (padrão publicar_versao)
  if array_length(erros, 1) > 0 then
    raise exception E'registo de checklist inválido:\n- %', array_to_string(erros, E'\n- ');
  end if;

  -- ----------------------------------------------------------------
  -- 6. Insere verificacao com foto de atribuição — mesmo contrato da
  --    registar_picagem: o caminho é devolvido para o kiosk fazer o
  --    upload ao bucket picagens (policy existente cobre o caminho)
  -- ----------------------------------------------------------------
  v_foto_path := v_empresa::text || '/' || v_loja::text || '/'
                 || v_trabalhador_id::text || '/' || v_verificacao_id::text || '.jpg';

  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id,
     momento_dispositivo, momento_servidor, foto_url)
  values
    (v_verificacao_id, v_empresa, v_trabalhador_id, v_loja,
     p_momento_dispositivo, now(), v_foto_path);

  -- ----------------------------------------------------------------
  -- 7. Insere checklist_instancia (due_at=null: agendador é R2c)
  -- ----------------------------------------------------------------
  insert into public.checklist_instancia
    (empresa_id, template_id, versao_id, loja_id, verificacao_id,
     due_at, estado, concluida_em)
  values
    (v_empresa, v_versao.template_id, p_versao_id, v_loja, v_verificacao_id,
     null, 'concluida', now())
  returning id into v_instancia_id;

  -- ----------------------------------------------------------------
  -- 8. Insere checklist_resposta (conforme do SERVIDOR) +
  -- 10. Insere notificacao por resposta não conforme (inline)
  -- ----------------------------------------------------------------
  for rec_resp in
    select value as elem
      from jsonb_array_elements(coalesce(p_respostas, '[]'::jsonb))
  loop
    v_resp_item_id := (rec_resp.elem->>'item_id')::uuid;
    v_resp_valor   := rec_resp.elem->>'valor';
    v_resp_foto    := rec_resp.elem->>'foto_url';
    v_conforme     := not (v_resp_item_id = any(v_nc_item_ids));

    insert into public.checklist_resposta
      (empresa_id, instancia_id, item_id, valor, foto_url, conforme)
    values
      (v_empresa, v_instancia_id, v_resp_item_id, v_resp_valor, v_resp_foto, v_conforme)
    returning id into v_resposta_id;

    v_n_respostas := v_n_respostas + 1;

    -- notificacao por resposta não conforme (passo 10 — envio é R2c)
    if not v_conforme then
      v_n_nao_conformes := v_n_nao_conformes + 1;

      insert into public.notificacao
        (empresa_id, origem_id, canal, estado, destinatario)
      values
        (v_empresa, v_resposta_id, 'email', 'pendente', null);
        -- destinatario=null: ver divergência no cabeçalho
    end if;
  end loop;

  -- ----------------------------------------------------------------
  -- 9. Insere acao_corretiva (uma por entrada em p_acoes)
  -- ----------------------------------------------------------------
  for rec_acao in
    select value as elem
      from jsonb_array_elements(coalesce(p_acoes, '[]'::jsonb))
  loop
    v_acao_item_id   := (rec_acao.elem->>'item_id')::uuid;
    v_acao_descricao := trim(rec_acao.elem->>'descricao');

    -- lookup da resposta inserida no passo 8
    select id into v_resposta_id
      from public.checklist_resposta
     where instancia_id = v_instancia_id
       and item_id      = v_acao_item_id
       and empresa_id   = v_empresa;

    insert into public.acao_corretiva
      (empresa_id, resposta_id, verificacao_id, descricao)
    values
      (v_empresa, v_resposta_id, v_verificacao_id, v_acao_descricao);

    v_n_acoes := v_n_acoes + 1;
  end loop;

  -- ----------------------------------------------------------------
  -- 11. Resumo
  -- ----------------------------------------------------------------
  return json_build_object(
    'instancia_id',   v_instancia_id,
    'verificacao_id', v_verificacao_id,
    'foto_path',      v_foto_path,
    'respostas',      v_n_respostas,
    'nao_conformes',  v_n_nao_conformes,
    'acoes',          v_n_acoes
  );
end
$function$;

revoke all on function public.registar_checklist(text, text, uuid, timestamptz, jsonb, jsonb)
  from public, anon;
grant execute on function public.registar_checklist(text, text, uuid, timestamptz, jsonb, jsonb)
  to authenticated;
