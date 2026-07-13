# R2a — notas de fecho (2026-07-13)

> Fase R2a do doc 13: schema `checklist_*` versionado, RPCs de versionamento,
> seed da tabela de autoridade e construtor de templates no admin.
> Branch `r2a/checklist-schema-builder`; PR e merge humanos.

## Feito

1. **Migração `20260713170000_checklist_schema.sql`** — remove o schema HACCP
   inicial (doc 01 §3.4; sem dados de produção — a Frente B nunca arrancou) e
   cria o schema do doc 13 §2: `limite_legal` (global), `checklist_template`,
   `checklist_template_versao`, `checklist_item`, `checklist_instancia`,
   `checklist_resposta`, `acao_corretiva`. RLS ativa + policy `admin_empresa`
   em todas (exceto `limite_legal`: `leitura_global` para authenticated,
   escrita por nenhuma role de cliente). Grants explícitos, incluindo **grants
   de coluna**: o `estado` da versão nunca é manipulável por cliente (INSERT
   nasce `rascunho`, UPDATE só de `frequencia_tipo`/`frequencia_config`);
   `checklist_item.versao_id`/`empresa_id` fora do UPDATE (item não pode ser
   "movido" por DML). Índices únicos parciais: um rascunho e uma publicada por
   template. FKs compostas `(empresa_id, id)` mantidas em toda a cadeia.
2. **Migração `20260713170100_checklist_comportamento.sql`** — triggers de
   imutabilidade (versões publicadas/arquivadas e itens congelados, incluindo
   INSERT de item em versão não-rascunho; respostas/ações corretivas
   append-only após instância concluída) + RPCs SECURITY DEFINER
   (`search_path=''`, escopo por `empresa_id`, guard `is_admin()`):
   `publicar_versao` (relatório de validação completo numa única exceção;
   arquiva a anterior atomicamente) e `criar_rascunho_de` (clona itens).
3. **Verificação na BD real** (`xghfsudvpsgqkslobttj`, read-only, pós-push):
   7 tabelas com RLS ativa; tabela antiga `checklist_template_loja` removida;
   policies corretas; 2 RPCs com `prosecdef=true` e `search_path=""`; 4
   triggers `trg_imutavel_*` novos; seed = 2 linhas da Portaria 1135/95;
   grants: `anon` sem nada, `authenticated` só-leitura em
   instância/resposta/ação/limite_legal, UPDATE da versão restrito a
   `frequencia_*`.
4. **Admin — secção `(painel)/checklists`**: lista (âmbito, versão publicada,
   rascunho), criação de template com versão 1 em rascunho, editor de rascunho
   (itens ordenáveis, tipos, limites, `booleano_conforme` só em booleanos,
   proveniência, ligação a `limite_legal` com pré-preenchimento), aviso quando
   mais exigente que o estatutário / bloqueio explicado quando menos exigente,
   publicar com relatório completo (`lib/erros.tsx`, multi-linha preservada),
   histórico de versões com "criar rascunho a partir de", frequência ao nível
   da versão com config mínima por tipo. Entrada "Checklists" na NAV.
5. **Testes** — `tests/10_checklist_versionamento_test.sql`: imutabilidade
   (5 caminhos), grants de coluna (publicação "à mão" barrada), `limite_legal`
   só-leitura, `publicar_versao` (sem itens; menos exigente que estatutário;
   `frequencia_config` incoerente; sucesso + arquivo da anterior), rascunho
   único (RPC e INSERT direto), kiosk sem poder publicar. Testes 01/02 e
   `supabase/seed.sql` adaptados ao schema novo; glob do `run_local.sh`
   alargado a `[0-9]*_test.sql`.
6. **Tipos** regenerados (`--linked` após o push). Gates finais verdes:
   `npm run build` (raiz) + `tests/run_local.sh` completos.

## Divergências (regra do CLAUDE.md: parar, registar, não improvisar)

1. **Doc 04 ausente do repo — RESOLVIDA em 2026-07-13.** No fecho inicial, o
   doc 04 não existia em lado nenhum e a biblioteca base ficou de fora (semear
   conteúdo HACCP de memória de modelo violaria a invariante 9). O fundador
   colocou `docs/04-levantamento-haccp.md` no repo (commit `ada039e`) e a
   pendência foi implementada na continuação:
   - **Migração `20260713190000_instalar_templates_base.sql`** — RPC SECURITY
     DEFINER que cria os 7 templates em rascunho (nunca publica), idempotente
     (advisory lock por empresa + no-op se a empresa já tiver templates).
     Valores e proveniência copiados do doc 04 §2/§4 e **verificados valor a
     valor pelo revisor-sql** — zero números fora do doc. Óleo de fritura
     ligado a `limite_legal` (lei); origem animal e água ≥ 82 °C como `lei`
     (Reg. 853/2004); temperaturas AHRESP e PRPs como `codigo_boas_praticas`.
   - **Botão "Instalar biblioteca base"** na lista de checklists (resultado
     por extenso; erros via `lib/erros.tsx`).
   - **Teste `tests/11_biblioteca_base_test.sql`** — 7 em rascunho, nenhum
     publicado, proveniência em todos os itens, idempotência, no-op em
     empresa com templates, kiosk barrado.
   - **Decisões de conteúdo (contra o §4 canónico — ver também o incidente
     de processo abaixo):** o §4 do doc 04 canónico nomeia expressamente os
     7 templates; a RPC realinhada (migração `20260713200000`) segue-os à
     letra: Temperaturas de frio (diário), Confeção e serviço (por turno),
     Óleo de fritura (diário, "só se aplicável"), Receção de mercadorias
     (por entrega — a origem animal são itens deste template, não template
     próprio), Higienização (por turno), Higiene pessoal / abertura (diário)
     e Pré-requisitos periódicos (semanal). Valores do §2 canónico
     (confeção/reaquecimento ≥ 75 °C; conservação a quente ≥ 65 °C;
     refrigeração 0–5 °C; congelados ≤ −18 °C; arrefecimento ≤ 10 °C em
     ≤ 2 h; descongelação ≤ 5 °C; óleo 180 °C / 25 % por lei). Os valores
     de origem animal não constam dos §2/§3 canónicos — verificados
     diretamente no texto indexado do Reg. 853/2004 (Anexo III, Secções
     I/II/V/VIII, `Project_2026/haccp/regul.853.2004.md`). Decisões
     preservadas, ainda válidas face ao doc canónico: **pescado fresco**
     sem limite numérico gravado (o regulamento diz "próxima da do gelo
     fundente"; o texto do item sinaliza-o); **leite cru** e o **tratamento
     de parasitas** fora da biblioteca; **temperaturas de receção** com
     `obrigatorio=false` (nem toda a entrega tem todas as categorias) e
     booleanos gerais da receção obrigatórios. Removidos face à primeira
     versão: os **82 °C** de higienização de utensílios (no Reg. 853/2004
     o contexto é matadouros; o §3.4 canónico não os tem) e os itens de
     armazenamento/alergénios/validades (não pertencem a nenhum template
     do §4 — o admin acrescenta conforme o plano).
   - **Correção pós-verificação:** os default privileges do Supabase davam
     EXECUTE a `anon` nas 3 RPCs novas (as definer antigas já revogavam
     `public, anon` — 20260712150200). A migração
     `20260713191000_rpcs_checklist_revogar_anon.sql` fecha o gap
     (invariante 6; sem exploração prática — todas exigem `is_admin`).
2. **Seed do Reg. 853/2004 (cadeia de frio) não semeado** — a instrução era
   semear apenas valores encontrados nos docs do repo com atribuição expressa
   à norma; nenhum doc do repo os tem. Entraram só as duas linhas da
   **Portaria 1135/95** (dadas como certas no prompt e **validadas contra o
   texto do DR** em `Project_2026/haccp/Portaria n.º 1135_95….md`: n.º 1.º —
   compostos polares ≤ 25 %; n.os 2.º/3.º — temperatura ≤ 180 ºC). As linhas
   853/2004 entram por migração futura, citando o regulamento diretamente.
3. **Schema antigo substituído** — doc 13 substitui o doc 01 §3.4: as tabelas
   `checklist_*` da migração `20260625090000` foram removidas (drop) por
   migração nova, incluindo `checklist_template_loja`, que o doc 13 não mantém
   (`loja_id` nullable no template cobre o caso). Sem dados de produção.
4. **Kiosk sem acesso a checklists no R2a** — as policies kiosk antigas
   (`kiosk_read` em template/item, `kiosk_insert` em instância/resposta/ação)
   caíram com as tabelas antigas e **não foram recriadas**: o kiosk está fora
   do âmbito do R2a; o R2b recria-as com o fluxo de preenchimento. O teste 02
   passou a esperar 0 templates visíveis pelo kiosk.

## Incidente de processo (2026-07-13)

**Duas migrações construídas sobre um doc desatualizado.** A migração
`20260713190000` (e a revisão que a validou) usou o `docs/04-levantamento-haccp.md`
então presente no repo, que estava desatualizado face à versão canónica do
fundador — agrupamento e vários valores divergiam (confeção 65 vs 75 °C,
refrigeração 0–7 vs 0–5 °C, congelados −12 vs −18 °C, 82 °C inexistente no
doc canónico, e o §4 real nomeia os 7 templates que o relatório inicial deu
como inexistentes). **Apanhado com zero dados afetados** — verificado na BD
real: nenhuma empresa tinha instalado a biblioteca; o problema ficou
confinado ao corpo da função. **Causa:** docs divergentes entre o repo e a
fonte do fundador. **Correção de fundo:** o repo passou a fonte única
(commits `ada039e` e `c83fa08`); correção técnica na migração
`20260713200000` (CREATE OR REPLACE realinhado, revisto valor a valor,
verificado na BD real: nomes do §4 presentes, valores canónicos presentes,
conteúdo antigo ausente). O teste 11 passou a ter *pins* de valores
canónicos (confeção ≥ 75, refrigeração 0–5, nomes do §4) para que um futuro
desalinhamento de conteúdo falhe a suite em vez de passar despercebido.

## Decisões de interpretação (registadas porque o doc 13 não fecha o detalhe)

- **Validação de `frequencia_config` no publicar:** `diaria` exige
  `vezes_por_dia` inteiro ≥ 1 e `janelas` (array `HH:MM`) com comprimento
  igual; `semanal` exige `dia_semana` 1–7 (1 = segunda, ISO); `por_turno` sem
  chaves obrigatórias; `por_evento` exige config vazia. O agendador (R2c)
  consome isto.
- **Hardening do revisor-sql aplicado** (sem violações bloqueantes): `drop if
  exists`, `CHECK (numero > 0)`, índices parciais com prefixo `empresa_id`,
  grants de coluna no UPDATE de `checklist_item`, índice em `limite_legal_id`.
- **Transição única permitida em versão publicada:** `publicada → arquivada`
  com todos os restantes campos inalterados (trigger compara campo a campo).

## Commits

- `163959b` — schema checklist_* versionado + imutabilidade e RPCs de versão
- `271f7df` — tipos regenerados (PG local, pré-push)
- `33ecc4c` — construtor de templates no admin
- `29dc3c1` — tipos canónicos (`--linked`, pós-push)
- `da66a14` — fecho inicial: docs 09 v3.2 + R2a-notas
- `67b4988` — RPC instalar_templates_base (biblioteca do doc 04)
- `e5ae894` — botão "Instalar biblioteca base" + tipo da RPC
- `b32d386` — revogar EXECUTE de anon nas RPCs de checklist
- `a216b0a` — R2a-notas: divergência 1 resolvida
- `c83fa08` — (fundador) doc 04 substituído pela versão canónica
- `24540b8` — realinhar instalar_templates_base ao doc 04 canónico
- (este fecho) — R2a-notas: incidente de processo + decisões corrigidas

## Gate da fase (doc 13 §5)

"Publicar um template real de temperaturas sem tocar em código" — exequível
de ponta a ponta no admin: criar template → editar rascunho (itens, limites,
proveniência, ligação à Portaria) → publicar com validação servidor. Provado
em SQL pelo teste 10 (T3: falha por limite menos exigente → correção →
publicação → arquivo da anterior).
