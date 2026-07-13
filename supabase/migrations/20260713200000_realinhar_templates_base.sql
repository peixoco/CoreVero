-- =====================================================================
-- 20260713200000_realinhar_templates_base.sql — R2a: realinhamento
--
-- CREATE OR REPLACE de instalar_templates_base(): a versão anterior
-- (20260713190000) foi construída sobre um docs/04 desatualizado.
-- O doc 04 canónico (commit c83fa08) nomeia expressamente os 7 templates
-- de arranque no §4 e traz valores diferentes nos §2/§3. Verificado na
-- BD real antes desta correção: ZERO templates instalados — o conteúdo
-- antigo nunca chegou a dados (incidente registado em docs/R2a-notas.md).
--
-- Realinhamentos de valores (§2 canónico):
--   confeção/reaquecimento ≥ 75 °C (antes 65); refrigeração 0–5 °C
--   (antes 0–7); congelados ≤ −18 °C (o −12 desaparece); arrefecimento
--   rápido ≤ 10 °C em ≤ 2 h (antes ≤ 5); descongelação ≤ 5 °C (novo);
--   óleo inalterado (Portaria 1135/95, lei, ligado a limite_legal).
--
-- Os 7 templates do §4 (nomes do doc):
--   1. Temperaturas de frio (diário)   4. Receção de mercadorias (por entrega)
--   2. Confeção e serviço (por turno)  5. Higienização (por turno)
--   3. Óleo de fritura (diário)        6. Higiene pessoal / abertura (diário)
--                                      7. Pré-requisitos periódicos (semanal)
--
-- Origem animal: passa a itens DENTRO da Receção de mercadorias (não é
-- template próprio). Estes valores não constam dos §2/§3 canónicos —
-- foram verificados diretamente contra o texto indexado do Reg. (CE)
-- 853/2004 (Project_2026/haccp/regul.853.2004.md): carne ≤ 7 °C e
-- miudezas ≤ 3 °C (Anexo III, Secção I); aves ≤ 4 °C (Secção II);
-- picada ≤ 2 °C / preparados ≤ 4 °C / congelação ≤ −18 °C (Secção V);
-- pescado congelado ≤ −18 °C e pescado fresco "temperatura próxima da
-- do gelo fundente" — sem número fixo (Secção VIII).
--
-- Decisões preservadas da versão anterior, ainda válidas face ao doc
-- canónico (registadas em R2a-notas contra o §4 real):
--   · pescado fresco sem limite numérico gravado (fixar no plano);
--   · leite cru e tratamento de parasitas fora da biblioteca;
--   · itens de temperatura da receção com obrigatorio=false (nem toda
--     a entrega tem todas as categorias); os booleanos gerais da
--     receção (§3.1: embalagem, validade, fornecedor, veículo) são
--     obrigatórios.
-- Removido nesta versão (não está no doc canónico):
--   · água ≥ 82 °C na higienização — no Reg. 853/2004 o contexto é a
--     esterilização de utensílios em matadouros; o §3.4 canónico
--     (higienização de restaurante) não o inclui;
--   · armazenamento (§3.2), alergénios, resíduos e rastreabilidade —
--     não pertencem a nenhum dos 7 templates do §4; o admin acrescenta
--     conforme o plano do estabelecimento.
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

  -- serializa chamadas simultâneas da mesma empresa
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
  -- 1. Temperaturas de frio — diário (doc 04 §4.1; valores §2)
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
    (v_emp, v_ver, 1, 'Conservação a frio / refrigeração — temperatura da câmara/equipamento', 'numerico', '°C',
     0, 5, true, 'codigo_boas_praticas', 'ASAE / códigos de boas práticas (0–5 °C; alguns produtos mais baixo — confirmar com o plano do estabelecimento)'),
    (v_emp, v_ver, 2, 'Congelação — temperatura do congelador', 'numerico', '°C',
     null, -18, true, 'codigo_boas_praticas', 'ASAE / códigos de boas práticas (≤ −18 °C)');
  v_nomes := v_nomes || 'Temperaturas de frio'::text;

  -- ------------------------------------------------------------------
  -- 2. Confeção e serviço — por turno (doc 04 §4.2; valores §2)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Confeção e serviço') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'por_turno', '{}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Confeção (cozedura) — temperatura no núcleo do alimento', 'numerico', '°C',
     75, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas PT (AHRESP/DGAV): ≥ 75 °C no centro'),
    (v_emp, v_ver, 2, 'Reaquecimento — temperatura no núcleo (uma única vez)', 'numerico', '°C',
     75, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas PT (AHRESP/DGAV): ≥ 75 °C'),
    (v_emp, v_ver, 3, 'Conservação a quente — temperatura de manutenção', 'numerico', '°C',
     65, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas PT (AHRESP/DGAV): ≥ 65 °C (UE geral: ≥ 63 °C)'),
    (v_emp, v_ver, 4, 'Arrefecimento rápido — temperatura do núcleo no fim (máximo 2 h)', 'numerico', '°C',
     null, 10, false, 'codigo_boas_praticas', 'Códigos de boas práticas (> 63 °C → ≤ 10 °C em ≤ 2 h); por lote arrefecido'),
    (v_emp, v_ver, 5, 'Descongelação — temperatura durante a descongelação (em refrigeração)', 'numerico', '°C',
     null, 5, false, 'codigo_boas_praticas', 'Códigos de boas práticas (≤ 5 °C; nunca à temperatura ambiente); por descongelação');
  v_nomes := v_nomes || 'Confeção e serviço'::text;

  -- ------------------------------------------------------------------
  -- 3. Óleo de fritura — LEI (Portaria 1135/95), ligado a limite_legal
  --    (doc 04 §4.3: "só se aplicável" — sem fritadeira, desativar)
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
    (v_emp, v_ver, 1, 'Óleo de fritura — temperatura do banho', 'numerico', '°C',
     null, 180, true, 'lei', 'Portaria 1135/95, n.os 2.º e 3.º', v_oleo_t),
    (v_emp, v_ver, 2, 'Óleo de fritura — compostos polares totais (TPM)', 'numerico', '%',
     null, 25, true, 'lei', 'Portaria 1135/95, n.º 1.º', v_oleo_p);
  v_nomes := v_nomes || 'Óleo de fritura'::text;

  -- ------------------------------------------------------------------
  -- 4. Receção de mercadorias — por entrega (doc 04 §4.4; itens §3.1;
  --    origem animal como itens deste template, valores Reg. 853/2004)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Receção de mercadorias') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'por_evento', '{}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Produtos refrigerados na entrega — temperatura', 'numerico', '°C',
     null, 5, false, 'codigo_boas_praticas', 'Códigos de boas práticas (≤ 5 °C, conforme produto)'),
    (v_emp, v_ver, 2, 'Produtos congelados na entrega — temperatura', 'numerico', '°C',
     null, -18, false, 'codigo_boas_praticas', 'Códigos de boas práticas (≤ −18 °C)'),
    (v_emp, v_ver, 3, 'Integridade da embalagem (sem danos)', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Doc 04 §3.1 — receção de mercadorias'),
    (v_emp, v_ver, 4, 'Prazo de validade dentro do limite', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Doc 04 §3.1 — receção de mercadorias'),
    (v_emp, v_ver, 5, 'Fornecedor aprovado e documentação presente', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Doc 04 §3.1 — receção de mercadorias'),
    (v_emp, v_ver, 6, 'Higiene do veículo de transporte conforme', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Doc 04 §3.1 — receção de mercadorias'),
    -- origem animal — LEI (Reg. 853/2004, Anexo III; verificado no texto indexado)
    (v_emp, v_ver, 7, 'Carne (peças) — temperatura à receção', 'numerico', '°C',
     null, 7, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção I (≤ 7 °C)'),
    (v_emp, v_ver, 8, 'Miudezas / vísceras — temperatura à receção', 'numerico', '°C',
     null, 3, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção I (≤ 3 °C)'),
    (v_emp, v_ver, 9, 'Aves de capoeira — temperatura à receção', 'numerico', '°C',
     null, 4, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção II (≤ 4 °C)'),
    (v_emp, v_ver, 10, 'Carne picada — temperatura à receção', 'numerico', '°C',
     null, 2, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção V (≤ 2 °C; congelada: ≤ −18 °C)'),
    (v_emp, v_ver, 11, 'Preparados de carne — temperatura à receção', 'numerico', '°C',
     null, 4, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção V (≤ 4 °C)'),
    (v_emp, v_ver, 12, 'Pescado fresco — temperatura à receção (anotar °C; sem limite legal fixo)', 'numerico', '°C',
     null, null, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção VIII — temperatura próxima da do gelo fundente (≈ 0 °C); limite exato a fixar no plano do estabelecimento'),
    (v_emp, v_ver, 13, 'Pescado congelado — temperatura à receção', 'numerico', '°C',
     null, -18, false, 'lei', 'Reg. (CE) 853/2004, Anexo III, Secção VIII (≤ −18 °C)');
  v_nomes := v_nomes || 'Receção de mercadorias'::text;

  -- ------------------------------------------------------------------
  -- 5. Higienização — por turno (doc 04 §4.5; itens §3.4; critério é
  --    o plano de limpeza do estabelecimento)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Higienização') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'por_turno', '{}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Superfícies de trabalho limpas e desinfetadas conforme o plano', 'booleano', null,
     null, null, true, 'plano_estabelecimento', 'Plano de limpeza do estabelecimento (base: Reg. 852/2004)'),
    (v_emp, v_ver, 2, 'Equipamentos limpos conforme o plano', 'booleano', null,
     null, null, true, 'plano_estabelecimento', 'Plano de limpeza do estabelecimento (base: Reg. 852/2004)'),
    (v_emp, v_ver, 3, 'Instalações (chão, casas de banho) limpas conforme o plano', 'booleano', null,
     null, null, true, 'plano_estabelecimento', 'Plano de limpeza do estabelecimento (base: Reg. 852/2004)'),
    (v_emp, v_ver, 4, 'Desinfetantes usados na concentração da ficha técnica', 'booleano', null,
     null, null, true, 'plano_estabelecimento', 'Ficha técnica do produto / plano de limpeza'),
    (v_emp, v_ver, 5, 'Termómetros higienizados entre amostras', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Doc 04 §3.4 — higienização');
  v_nomes := v_nomes || 'Higienização'::text;

  -- ------------------------------------------------------------------
  -- 6. Higiene pessoal / abertura — diário (doc 04 §4.6; itens §3.3)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Higiene pessoal / abertura') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'diaria', '{"vezes_por_dia":1,"janelas":["08:00"]}')
    returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Lavagem de mãos nos momentos-chave', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas (AHRESP/DGAV) — higiene dos manipuladores'),
    (v_emp, v_ver, 2, 'Fardamento limpo e adequado', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas (AHRESP/DGAV) — higiene dos manipuladores'),
    (v_emp, v_ver, 3, 'Estado de saúde: sem sintomas relevantes (pessoal apto)', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas (AHRESP/DGAV) — higiene dos manipuladores'),
    (v_emp, v_ver, 4, 'Uso correto de luvas', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas (AHRESP/DGAV) — higiene dos manipuladores'),
    (v_emp, v_ver, 5, 'Feridas protegidas', 'booleano', null,
     null, null, true, 'codigo_boas_praticas', 'Códigos de boas práticas (AHRESP/DGAV) — higiene dos manipuladores');
  v_nomes := v_nomes || 'Higiene pessoal / abertura'::text;

  -- ------------------------------------------------------------------
  -- 7. Pré-requisitos periódicos — semanal (doc 04 §4.7: pragas, água,
  --    calibração, formação; itens §3.5)
  -- ------------------------------------------------------------------
  insert into public.checklist_template (empresa_id, nome)
    values (v_emp, 'Pré-requisitos periódicos') returning id into v_tpl;
  insert into public.checklist_template_versao
      (empresa_id, template_id, numero, frequencia_tipo, frequencia_config)
    values (v_emp, v_tpl, 1, 'semanal', '{"dia_semana":1}') returning id into v_ver;
  insert into public.checklist_item
      (empresa_id, versao_id, ordem, texto, tipo_resposta, unidade,
       limite_min, limite_max, booleano_conforme, obrigatorio, limite_fonte, limite_referencia) values
    (v_emp, v_ver, 1, 'Sinais de atividade de pragas detetados?', 'booleano', null,
     null, null, false, true, 'codigo_boas_praticas', 'Doc 04 §3.5 — controlo de pragas; "sim" = não conforme'),
    (v_emp, v_ver, 2, 'Controlo de pragas: visitas e relatórios da empresa especializada em dia', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'Doc 04 §3.5 — controlo de pragas'),
    (v_emp, v_ver, 3, 'Controlo da água: potabilidade conforme o plano', 'booleano', null,
     null, null, true, true, 'plano_estabelecimento', 'Doc 04 §3.5 — controlo da água (rede ou análises, conforme plano)'),
    (v_emp, v_ver, 4, 'Termómetros calibrados e manutenção de equipamentos em dia', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'Doc 04 §3.5 — manutenção e calibração'),
    (v_emp, v_ver, 5, 'Formação de manipuladores atualizada', 'booleano', null,
     null, null, true, true, 'codigo_boas_praticas', 'Doc 04 §3.5 — formação');
  v_nomes := v_nomes || 'Pré-requisitos periódicos'::text;

  return json_build_object(
    'instalados', array_length(v_nomes, 1),
    'templates', to_json(v_nomes),
    'nota', 'todos em rascunho — reveja os limites contra o plano do estabelecimento e publique'
  );
end
$function$;

-- CREATE OR REPLACE preserva as ACLs (fechadas em 20260713191000);
-- re-afirmadas por explicitude (invariante 6)
revoke all on function public.instalar_templates_base() from public, anon;
grant execute on function public.instalar_templates_base() to authenticated;
