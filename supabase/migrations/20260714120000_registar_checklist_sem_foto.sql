-- =====================================================================
-- 20260714120000_registar_checklist_sem_foto.sql — R2b1: checklist
--   autenticada só por código + PIN (sem foto de atribuição)
--
-- Porquê (decisão do fundador, R2b1 — doc 13 §3, emenda ao fluxo):
--   · a foto de atribuição é EXCLUSIVA da picagem (anti-fraude do
--     registo de tempos, auditoria aleatória);
--   · nas checklists a autenticação é código + PIN; a verificacao
--     nasce com foto_url = null (minimização RGPD);
--   · fotos em checklists existem apenas ao nível do item
--     (tipo_resposta='foto', câmara traseira — pendente para R2c+).
--
-- O que muda face a 20260713210000_motor_conformidade_kiosk.sql:
--   · a verificacao é inserida com foto_url = null (a coluna já é
--     nullable desde 20260625090000 — sem alteração de schema);
--   · o resumo devolvido deixa de incluir foto_path (o kiosk já não
--     faz upload de foto de atribuição em checklists).
-- Tudo o resto (guards, validação de PIN, validações acumuladas,
-- avaliação server-side, inserções e notificações) mantém-se igual.
--
-- Invariantes respeitadas:
--   · 3: SECURITY DEFINER com set search_path to '' e todas as
--     queries escopadas por empresa_id.
--   · 6: revoke/grant explícitos re-afirmados no fim (o create or
--     replace preserva a ACL, mas o padrão do repo é explícito).
--   · D3 (doc 13): o kiosk NUNCA envia conforme — o servidor avalia.
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
  -- 6. Insere verificacao SEM foto de atribuição (foto_url = null) —
  --    autenticação por código + PIN; a foto de atribuição é exclusiva
  --    da picagem (decisão do fundador, R2b1; doc 13 §3)
  -- ----------------------------------------------------------------
  insert into public.verificacao
    (id, empresa_id, trabalhador_id, loja_id,
     momento_dispositivo, momento_servidor, foto_url)
  values
    (v_verificacao_id, v_empresa, v_trabalhador_id, v_loja,
     p_momento_dispositivo, now(), null);

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
        -- destinatario=null: divergência registada em 20260713210000
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
  -- 11. Resumo (sem foto_path: não há upload de foto de atribuição)
  -- ----------------------------------------------------------------
  return json_build_object(
    'instancia_id',   v_instancia_id,
    'verificacao_id', v_verificacao_id,
    'respostas',      v_n_respostas,
    'nao_conformes',  v_n_nao_conformes,
    'acoes',          v_n_acoes
  );
end
$function$;

-- Invariante 6 — grants explícitos re-afirmados (a assinatura não mudou,
-- a ACL persiste no create or replace; explícito por padrão do repo).
revoke all on function public.registar_checklist(text, text, uuid, timestamptz, jsonb, jsonb)
  from public, anon;
grant execute on function public.registar_checklist(text, text, uuid, timestamptz, jsonb, jsonb)
  to authenticated;
