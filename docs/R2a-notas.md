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
   - **Decisões de conteúdo (a validar no PR):** o doc 04 lista controlos,
     não nomeia 7 templates — agrupados por rotina de trabalho (frio; quente;
     óleo; receção origem animal; higienização/instalações; pragas/manutenção;
     higiene pessoal). **Pescado fresco** sem limite numérico gravado (o doc
     diz "≈ 0 °C" — fixar no plano do estabelecimento; nota na referência do
     item). **Leite cru** (valor ambíguo 6–8 °C, raro em restauração) e o
     **tratamento de parasitas** (−20 °C/24 h, controlo de processo, não de
     receção) ficaram fora da biblioteca. Itens de receção como
     `obrigatorio=false` (nem toda a entrega tem todas as categorias).
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
- (este fecho) — R2a-notas: divergência 1 resolvida

## Gate da fase (doc 13 §5)

"Publicar um template real de temperaturas sem tocar em código" — exequível
de ponta a ponta no admin: criar template → editar rascunho (itens, limites,
proveniência, ligação à Portaria) → publicar com validação servidor. Provado
em SQL pelo teste 10 (T3: falha por limite menos exigente → correção →
publicação → arquivo da anterior).
