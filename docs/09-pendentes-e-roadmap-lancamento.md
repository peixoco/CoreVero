# 09 — Pendentes e Roadmap de Lançamento (v3.2, R0/R1/R2a fechados)

> **Substitui a v2.** R0 executado de ponta a ponta em 2026-07-12 (7 commits, detalhe em `docs/R0-notas.md`), com verificação independente na BD real (`xghfsudvpsgqkslobttj`) por consulta read-only. R1 fechado no mesmo dia (detalhe em `docs/R1-notas.md`). R2a fechado em 2026-07-13 (detalhe em `docs/R2a-notas.md`). Relacionados: `08-roadmap.md`, `06-jurisdicao-rh.md`, `10-visao-potencial-plataforma.md`, `13-desenho-r2-haccp.md`, `docs/09-levantamento-*.md`.

---

## 1. Pendentes do R0 — estado final

| # | Pendente | Estado |
|---|---|---|
| P1 | `sequencia_valida`/`iniciar_picagem` não excluíam anuladas | **Fechado** (`7397d44`) — verificado na BD: `anulada` presente nos dois corpos |
| P2 | `picagem_recusada` via default privileges (revogação Supabase 2026-10-30) | **Fechado** (`7397d44`) — verificado: `authenticated`=SELECT, `anon` sem nada |
| P3 | 9 sítios no admin a engolir erros | **Fechado** (`b542e01`) — `lib/erros.tsx` uniforme |
| P4 | Edição de colaborador regredida em `032097d`; RPCs órfãs | **Fechado** (`a733bb3`) — página recuperada; `criar_colaborador`/`gerar_novo_pin`/`atualizar_colaborador` convertidas para SECURITY DEFINER (`7397d44`) |
| P5 | `NovaPicagemModal` com timezone naïf | **Fechado** (`b759612`) — `paredeParaUTC` em `packages/core` |
| P6 | Recusas terminais nunca limpas no kiosk (badge perpétuo) | **Fechado** (`ad1762f`) |
| P7 | Testes 06/08 contra assinatura dropada | **Fechado** (`611865a`) — 06/08 reescritos, novo `07_sequencia_anuladas_test.sql`, `tests/run_local.sh`; 03/04/05 atualizados ao modelo atual de PIN |
| P8 | Casca de navegação | **Fechado sem alteração** — verificado já satisfeito no estado atual; o doc 08 descrevia o estado anterior a `032097d` |
| P9 | Decisão do PIN display-once | **Fechado** (`a733bb3` UI mascarada + `1d46786` emenda ao doc 08 §6: "PIN nunca recuperável após criação") |

**Fecho complementar do P4/P9 (segurança):** escrita direta de `trabalhador.pin` por `authenticated` revogada (`7397d44`); resta um REFERENCES residual, inócuo. Verificado na BD.

**Aceites sem ação (inalterados):**
- Edge case offline: cache não refrescada <5 min antes do corte → recusa visível no drain, não perda silenciosa.
- Dívida de testes da fase 2+ além do `07_...` novo — listada em `docs/R0-notas.md`.

**Nota operacional:** ~~a raiz do monorepo não tem script `build`~~ resolvido no R1 — `npm run build` na raiz corre o build do admin + typecheck do kiosk. A suite SQL corre com `tests/run_local.sh` (Postgres descartável; salta migrações pg_cron/pg_net, indisponíveis fora do Supabase).

---

## 2. Roadmap de releases

### ~~R0 — Saneamento~~ ✅ Fechado 2026-07-12

### ~~R1 — Fecho da Frente A (S)~~ ✅ Fechado 2026-07-12
`vista_picagem.desvio_segundos` (migração `20260712160000`, verificada na BD real) + badge informativo no admin acima de 300 s (`LIMIAR_DESVIO_SEGUNDOS` em `packages/core`; passa a configuração por empresa no R3) + teste do DoD `tests/09_dod_frente_a_test.sql` (mês sintético: pausas descontadas, dois turnos, anulada + correção, desvio injetado de 420 s). Detalhe e divergências em `docs/R1-notas.md`.

### R2 — Frente B: HACCP (XL) — faseado pelo doc 13
Pela ordem fechada: schema `checklist_*` + proveniência de limites → construtor de templates → motor de conformidade + ação corretiva forçada → preenchimento no kiosk → notificações (Resend) → agendamento + `em_falta` → **Vera + RAG** por último, sobre motor estável.

- ~~**R2a** — schema versionado + construtor de templates + biblioteca base~~ ✅ Fechado 2026-07-13 (`docs/R2a-notas.md`): migrações `20260713170000`–`20260713191000` verificadas na BD real; secção Checklists no admin com "Instalar biblioteca base" (7 templates do doc 04, sempre em rascunho). Divergência do doc 04 resolvida com a entrada de `docs/04-levantamento-haccp.md` no repo.
- ~~**R2b** — motor de conformidade + preenchimento no kiosk (online-only) + ação corretiva forçada~~ ✅ Código fechado 2026-07-13 (`docs/R2b-notas.md`): migração `20260713210000` (motor + `obter_checklists_kiosk` + `registar_checklist`), secção Checklists no kiosk, tab Preenchimentos no admin, 22 testes. Migração aplicada 2026-07-14 (push aprovado); verificação `verificador-bd` 10/10; tipos `--linked` regenerados.
- **R2c** — agendador (instâncias + `em_falta`) + notificações Resend + relatório do dia ← **atual** (traz do R2b: idempotência do `registar_checklist`, `destinatario` das notificações, decisão do nome da RPC vs doc 13)
- **R2d** — Vera + RAG sobre motor estável

### R3 — Frente C: camada RH (L)
Tabela cifrada de fiscais, bucket de documentos, aptidão/certificados com alertas, horário e férias, página do colaborador completa, 4 relógios de retenção independentes.

### R4 — Dashboard do Início (M) — depende de A + B.

### R5 — Lançamento comercial (L)
Stripe + enforcement; DPA + art. 13.º (**parecer jurídico em paralelo, arrancar já**); EUIPO antes de materiais definitivos; builds EAS.

---

## 3. Riscos

- **Dispersão:** com o R0 e a Frente A quase fechados, a tentação de saltar para a visão (doc 10) antes do HACCP cresce. O diferenciador do produto continua por começar. *[Certain]*
- **Jurídico em cima do lançamento:** prazo de calendário, não de código — não deixar para R5. *[Likely]*
- **Regressões silenciosas:** o gate build+testes melhorou (P7), mas a fase 2+ continua com cobertura fina; a segunda regressão do tipo `032097d` continua possível. *[Likely]*

---

## 4. O que fica explicitamente FORA (vive no doc 10)

Chat interno, agentes além da Vera, food cost, labour cost sobre vendas, portal do colaborador, recibos, assinatura eletrónica, integrações POS. Nada entra antes de R1+R2 em produção.
