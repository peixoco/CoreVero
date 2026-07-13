-- =====================================================================
-- 20260713190000_instalar_templates_base.sql — R2a: biblioteca base
--
-- RPC instalar_templates_base(): cria para a empresa do chamador os
-- 7 templates de arranque, cada um com UMA versão em RASCUNHO com os
-- itens e valores do doc 04 (docs/04-levantamento-haccp.md, §2 e §4).
--
-- Regras (doc 13 §4.4 + prompt R2a):
--   · NUNCA publica nada — os limites são responsabilidade do plano do
--     estabelecimento; o admin revê, ajusta e publica.
--   · Idempotente: se a empresa já tiver templates, não duplica (no-op).
--   · Proveniência por item conforme o doc 04:
--       'lei'                  → Portaria 1135/95 (óleo, ligado a
--                                limite_legal) e Reg. (CE) 853/2004
--                                (origem animal, água ≥ 82 °C);
--       'codigo_boas_praticas' → Código de Boas Práticas AHRESP
--                                (temperaturas de frio/quente e PRPs).
--   · Nenhum valor inventado: todos os números vêm da tabela do doc 04.
--     Pescado fresco ("próximo do gelo fundente, ≈ 0 °C") não tem limite
--     numérico gravado — o doc não fixa um número exato; fica em nota
--     na referência para o plano do estabelecimento fixar.
--     Leite cru (≤ 6–8 °C, ambíguo e raro em restauração) e o tratamento
--     de parasitas (≤ −20 °C / ≥ 24 h, controlo de processo e não de
--     receção) ficam de fora da biblioteca — registado em R2a-notas.
--
-- Agrupamento em 7 templates (o doc 04 lista controlos, não templates;
-- agrupados por rotina de trabalho — decisão registada em R2a-notas):
--   1. Temperaturas de frio (diária 2x)      — §2 refrigeração/congelação
--   2. Confeção e serviço a quente (por turno) — §2 quente + arrefecimento
--   3. Óleo de fritura (diária 1x)           — §2 lei, ligado a limite_legal
--   4. Receção de origem animal (por evento) — §2 tabela Reg. 853/2004
--   5. Higienização e instalações (diária 1x) — PRPs 1/2/7/8 + água 82 °C
--   6. Pragas e manutenção (semanal)         — PRPs 3/4
--   7. Higiene pessoal e práticas (diária 1x) — PRPs 6/9/14
-- =====================================================================

create or replace function public.instalar_templates_base()
returns json
language plpgsql security definer set search_path to '' as $function$
declare
  v_emp    uuid := public.empresa_atual();
  v_tpl    uuid;
  v_ver    uuid;
  v_oleo_t uuid;
  v_oleo_p uuid;
  v_nomes  text[] := '{}';
begin
  if not public.is_admin() then
    raise exception 'apenas administradores podem instalar a biblioteca base'
      using errcode = 'insufficient_privilege';
  end if;
  if v_emp is null then
    raise exception 'sessão sem empresa' using errcode = 'insufficient_privilege';
  end if;

  -- serializa chamadas simultâneas da mesma empresa (o guard de idempotência
  -- abaixo não tem lock; sem isto, duas transações concorrentes duplicariam)
  perform pg_advisory_xact_lock(hashtext('instalar_templates_base:' || v_emp::text));

  -- idempotência: empresa com templates não recebe a biblioteca outra vez
  if exists (select 1 from public.checklist_template where empresa_id = v_emp) then
    return json_build_object(
      'instalados', 0,
      'motivo', 'a empresa já tem templates — biblioteca base não instalada para não duplicar'
    );
  end if;

  select id into v_oleo_t from public.limite_legal where controlo = 'oleo_fritura_temperatura';
  select id into v_oleo_p from public.limite_legal where controlo = 'oleo_fritura_compostos_polares';
  if v_oleo_t is null or v_oleo_p is null then
    raise exception 'limite_legal sem as linhas da Portaria 1135/95 — seed em falta';
  end if;

  -- ------------------------------------------------------------------
  -- 1. Temperaturas de frio — Código AHRESP (doc 04 §2)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Temperaturas de frio') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'diaria', '{"vezes_por_dia":2,"janelas":["08:00","16:00"]}')
    returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Refrigeração (câmara/frigorífico) — temperatura', 'numerico', '°C',
     0, 7, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (0–7 °C)'),
    (v_emp, v_ver, 2, 'Congelados — temperatura', 'numerico', '°C',
     null, -12, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (≤ −12 °C; origem animal: ≤ −18 °C por lei, Reg. 853/2004)'),
    (v_emp, v_ver, 3, 'Ultracongelados — temperatura', 'numerico', '°C',
     null, -18, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (≤ −18 °C)');
  v_nomes := v_nomes || 'Temperaturas de frio'::text;

  -- ------------------------------------------------------------------
  -- 2. Confeção e serviço a quente — Código AHRESP (doc 04 §2)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Confeção e serviço a quente') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'por_turno', '{}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Confeção — temperatura no interior do alimento', 'numerico', '°C',
     65, null, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (≥ 65 °C; planos Codex usam 75 °C — desempate no plano do estabelecimento)'),
    (v_emp, v_ver, 2, 'Reaquecimento — temperatura no interior (abaixo do limite: eliminar)', 'numerico', '°C',
     65, null, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (≥ 65 °C)'),
    (v_emp, v_ver, 3, 'Conservação a quente — temperatura', 'numerico', '°C',
     65, null, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (≥ 65 °C)'),
    (v_emp, v_ver, 4, 'Arrefecimento rápido — temperatura no fim (máximo 2 h após confeção)', 'numerico', '°C',
     null, 5, true, 'codigo_boas_praticas', 'Código de Boas Práticas AHRESP (até 5 °C em ≤ 2 h)');
  v_nomes := v_nomes || 'Confeção e serviço a quente'::text;

  -- ------------------------------------------------------------------
  -- 3. Óleo de fritura — LEI (Portaria 1135/95), ligado a limite_legal
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Óleo de fritura') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'diaria', '{"vezes_por_dia":1,"janelas":["11:00"]}')
    returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia, limite_legal_id) values
    (v_emp, v_ver, 1, 'Óleo de fritura — temperatura da gordura/óleo', 'numerico', '°C',
     null, 180, true, 'lei', 'Portaria 1135/95, n.os 2.º e 3.º', v_oleo_t),
    (v_emp, v_ver, 2, 'Óleo de fritura — teor de compostos polares', 'numerico', '%',
     null, 25, true, 'lei', 'Portaria 1135/95, n.º 1.º', v_oleo_p);
  v_nomes := v_nomes || 'Óleo de fritura'::text;

  -- ------------------------------------------------------------------
  -- 4. Receção de matérias-primas de origem animal — LEI (Reg. 853/2004)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Receção de matérias-primas (origem animal)') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'por_evento', '{}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Carne (peças) — temperatura à receção', 'numerico', '°C',
     null, 7, false, 'lei', 'Reg. (CE) 853/2004 (≤ 7 °C)'),
    (v_emp, v_ver, 2, 'Miudezas / vísceras — temperatura à receção', 'numerico', '°C',
     null, 3, false, 'lei', 'Reg. (CE) 853/2004 (≤ 3 °C)'),
    (v_emp, v_ver, 3, 'Aves de capoeira — temperatura à receção', 'numerico', '°C',
     null, 4, false, 'lei', 'Reg. (CE) 853/2004 (≤ 4 °C)'),
    (v_emp, v_ver, 4, 'Carne picada — temperatura à receção', 'numerico', '°C',
     null, 2, false, 'lei', 'Reg. (CE) 853/2004 (≤ 2 °C; congelada: ≤ −18 °C)'),
    (v_emp, v_ver, 5, 'Preparados de carne — temperatura à receção', 'numerico', '°C',
     null, 4, false, 'lei', 'Reg. (CE) 853/2004 (≤ 4 °C)'),
    (v_emp, v_ver, 6, 'Pescado fresco — temperatura à receção', 'numerico', '°C',
     null, null, false, 'lei', 'Reg. (CE) 853/2004 — próximo do gelo fundente (≈ 0 °C); limite exato a fixar no plano do estabelecimento'),
    (v_emp, v_ver, 7, 'Pescado congelado — temperatura à receção', 'numerico', '°C',
     null, -18, false, 'lei', 'Reg. (CE) 853/2004 (≤ −18 °C)');
  v_nomes := v_nomes || 'Receção de matérias-primas (origem animal)'::text;

  -- ------------------------------------------------------------------
  -- 5. Higienização e instalações — PRPs 1/2/7/8 (AHRESP) + água ≥ 82 °C (lei)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Higienização e instalações') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'diaria', '{"vezes_por_dia":1,"janelas":["22:00"]}')
    returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, booleano_conforme, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Instalações e equipamentos em bom estado, com separação cru/cozinhado', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 1 (Reg. 852/2004, Anexo II)'),
    (v_emp, v_ver, 2, 'Plano de limpeza e desinfeção do dia cumprido (com evidência)', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 2 (Reg. 852/2004, Anexo II)'),
    (v_emp, v_ver, 3, 'Higienização de utensílios — temperatura da água', 'numerico', '°C',
     82, null, null, true, 'lei', 'Reg. (CE) 853/2004 (água ≥ 82 °C)'),
    (v_emp, v_ver, 4, 'Gestão de resíduos conforme (recolha e acondicionamento)', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 7 (Reg. 852/2004, Anexo II)'),
    (v_emp, v_ver, 5, 'Controlo da água — potabilidade sem anomalias', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 8 (Reg. 852/2004, Anexo II)');
  v_nomes := v_nomes || 'Higienização e instalações'::text;

  -- ------------------------------------------------------------------
  -- 6. Controlo de pragas e manutenção — PRPs 3/4 (AHRESP)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Controlo de pragas e manutenção') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'semanal', '{"dia_semana":1}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, booleano_conforme, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Sinais de atividade de pragas detetados?', 'booleano', null,
     null, null, false, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 3 (Reg. 852/2004, Anexo II); "sim" = não conforme'),
    (v_emp, v_ver, 2, 'Contrato de controlo de pragas e relatórios em dia', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 3 (Reg. 852/2004, Anexo II)'),
    (v_emp, v_ver, 3, 'Manutenção técnica em dia e termómetros calibrados', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 4 (Reg. 852/2004, Anexo II)');
  v_nomes := v_nomes || 'Controlo de pragas e manutenção'::text;

  -- ------------------------------------------------------------------
  -- 7. Higiene pessoal e práticas de trabalho — PRPs 6/9/14 (AHRESP)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Higiene pessoal e práticas de trabalho') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'diaria', '{"vezes_por_dia":1,"janelas":["08:00"]}')
    returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, booleano_conforme, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Higiene pessoal e fardamento conformes; pessoal sem sinais de doença', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 9 (Reg. 852/2004, Anexo II)'),
    (v_emp, v_ver, 2, 'Separação de alergénios e prevenção de contaminação cruzada respeitadas', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 6 (Reg. 852/2004, Anexo II)'),
    (v_emp, v_ver, 3, 'Prazos de validade verificados (FIFO/FEFO, sem produtos expirados)', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'AHRESP — PRP n.º 14 (Reg. 852/2004, Anexo II)');
  v_nomes := v_nomes || 'Higiene pessoal e práticas de trabalho'::text;

  return json_build_object(
    'instalados', array_length(v_nomes, 1),
    'templates', to_json(v_nomes),
    'nota', 'todos em rascunho — reveja os limites contra o plano do estabelecimento e publique'
  );
end
$function$;

revoke all on function public.instalar_templates_base() from public;
grant execute on function public.instalar_templates_base() to authenticated;
