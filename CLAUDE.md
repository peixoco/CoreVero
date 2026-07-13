# CoreVero — memória de projeto

SaaS multi-tenant (isolamento por `empresa_id` + RLS) para restauração em Portugal: relógio de ponto autenticado (Frente A, fechada) + HACCP configurável (Frente B, atual — R2a fechado, R2b em curso). Fundador solo. A fonte de verdade de arquitetura, roadmap e decisões são os docs numerados em `docs/` (00–13); o estado real do código está em `docs/09-*.md` e nas notas de release (`docs/R*-notas.md`). **O repo é a fonte única dos docs** — antes de semear conteúdo a partir de um doc numerado, confirmar que é a versão em `docs/`.

## Estrutura
- `apps/admin` — Next.js 16 App Router (painel do gestor)
- `apps/kiosk` — Expo SDK 56 (tablet partilhado, sessão permanente)
- `packages/core` — código partilhado (tipos, helpers, constantes)
- `supabase/migrations` — migrações SQL (Postgres 17, projeto eu-west-3)

## Comandos
- Gate obrigatório antes de qualquer push: `npm run build` (raiz) e a suite SQL via `tests/run_local.sh` (Docker: Postgres descartável)
- Aplicar migrações: `npx supabase db push` (pausa para aprovação humana)
- Regenerar tipos após alteração de schema: `npx supabase gen types typescript --linked`
- Gestor de pacotes: **npm** (o repo tem `package-lock.json`)

## Acesso à base de dados (regra estrita)
- **Nunca usar servidores MCP para consultar a BD** — os resultados MCP ficam no contexto da sessão inteira e são o maior custo do projeto. Qualquer verificação da BD real é delegada ao subagente `verificador-bd` (liga por `psql "$VERIFICA_DB_URL"`, role read-only por privilégio, contexto descartável).
- A thread principal não corre `psql` de leitura exploratória — se precisa de saber o que está na BD, delega ao `verificador-bd` com pontos concretos.

## Ciclo de trabalho git (obrigatório)
1. Arranque de qualquer trabalho: `git checkout main && git pull`.
2. Criar sempre uma branch nova: `git checkout -b <release>/<descricao-curta>` (ex.: `r2b/motor-conformidade`). **Nunca trabalhar diretamente em `main`.**
3. Commits por unidade lógica, mensagens em português europeu, prefixo da release (ex.: `R2b:`).
4. **Sem atribuição de AI nos commits**: nenhum trailer `Co-Authored-By`, nenhuma linha "Generated with Claude Code". (Reforçado por `includeCoAuthoredBy: false` no settings.)
5. Após cada `db push`: **delegação obrigatória ao `verificador-bd`** com a lista do que verificar; um ✗ no relatório trava o avanço até correção (por migração nova).
6. Fecho: gates verdes + verificação da BD conforme → `git push -u origin <branch>` → **perguntar ao humano se cria o Pull Request**. Só com confirmação explícita: criar via `gh pr create` (base `main`) com descrição estruturada: resumo (3–5 linhas), alterações por commit, evidência dos gates (build, suite, relatório do verificador-bd), divergências/decisões a validar, focos de revisão sugeridos.
7. Depois de criar o PR (ou sem confirmação para o criar): **parar**. A revisão e o **merge são sempre humanos**. `git push` para `main` é proibido em qualquer circunstância.

## Regras de trabalho
- Português europeu em código, comentários, commits e respostas.
- Migrações: `supabase/migrations/YYYYMMDDHHMMSS_nome.sql`, timestamp posterior à última migração aplicada. Nunca editar uma migração já aplicada — correções são sempre migração nova (ex.: `create or replace`).
- Ficheiros sempre completos; nunca patches parciais deixados a meio.
- Erros nunca são engolidos: mostrar sempre o texto completo do erro, nunca só contagens (helper `lib/erros.tsx` no admin).
- Se a especificação de uma tarefa divergir da realidade do código: parar, reportar a divergência, não improvisar.
- Embeds PostgREST sobre FKs compostas: usar o nome da constraint (padrão resolvido no R2a) — nunca o nome da coluna.

## Invariantes de segurança (violação = bloqueante)
1. O kiosk está confinado a picagem + preenchimento de checklists. Funções de RH/administração nunca aparecem no kiosk. Leitura de checklists no kiosk só por RPC dedicada — nunca SELECT direto.
2. `trabalhador.pin` nunca é legível por roles de cliente; escrita só via RPC SECURITY DEFINER. O PIN nunca é recuperável após criação (display-once mascarado).
3. Toda a função SECURITY DEFINER tem `set search_path to ''` e escopa todas as queries por `empresa_id` (um definer ignora RLS).
4. `picagem` é append-only (trigger de imutabilidade); versões de checklist publicadas/arquivadas e respostas após fecho idem. Correção = novo registo, nunca UPDATE/DELETE.
5. Qualquer lookup de picagem anterior exclui anuladas: `and not p.anulada`.
6. Grants explícitos em tabelas, views **e funções** (revogar EXECUTE de `public`/`anon` em RPCs novas); nunca depender de default privileges.
7. Conversão hora-de-parede→UTC só via helper `paredeParaUTC` (`packages/core`, Europe/Lisbon, DST-aware); nunca `new Date().toISOString()` para horas de parede.
8. Nada de biometria nem reconhecimento facial — é compromisso contratual (DPA cl. 3) e pressuposto da AIPD; violá-lo reabre todo o quadro jurídico.
9. Vera e qualquer agente de AI do produto: números e limites legais só de fonte citada ou tabela de autoridade (`limite_legal` / plano do estabelecimento), nunca de memória de modelo; humano aprova sempre. O mesmo vale para conteúdo HACCP semeado por migração: só de docs canónicos, zero números de memória.
10. Retenções legais são relógios independentes e configuráveis (6 relógios — ver doc 12, mapa consolidado); nunca um schedule único nem valores cravados.
11. NIF/NISS/IBAN vivem apenas na tabela cifrada com role próprio; nunca expostos ao kiosk. O verificador-bd nunca imprime conteúdo de colunas sensíveis.

## Delegação a subagentes
- Exploração e pesquisa no repo: `explorador`.
- Toda a migração SQL nova passa pelo `revisor-sql` **antes** do `supabase db push`.
- Verificação da BD real (pós-push, ou qualquer consulta ao estado remoto): `verificador-bd` — sempre, sem exceção; a thread principal nunca consulta a BD diretamente.
- Implementação de tarefas com especificação fechada: `executor`, uma tarefa de cada vez, com o texto completo da tarefa.
- A thread principal reserva-se para: planeamento, decisões de arquitetura, síntese e verificação final.
- Tarefas pequenas e pontuais: thread principal, sem delegar.
