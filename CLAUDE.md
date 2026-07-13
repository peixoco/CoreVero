# CoreVero — memória de projeto

SaaS multi-tenant (isolamento por `empresa_id` + RLS) para restauração em Portugal: relógio de ponto autenticado (Frente A, fechada) + HACCP configurável (Frente B, atual). Fundador solo. A fonte de verdade de arquitetura, roadmap e decisões são os docs numerados em `docs/` (00–12); o estado real do código está em `docs/09-*.md` e nas notas de release (`docs/R*-notas.md`).

## Estrutura

- `apps/admin` — Next.js 16 App Router (painel do gestor)
- `apps/kiosk` — Expo SDK 56 (tablet partilhado, sessão permanente)
- `packages/core` — código partilhado (tipos, helpers, constantes)
- `supabase/migrations` — migrações SQL (Postgres 17, projeto eu-west-3)

## Comandos

- Gate obrigatório antes de qualquer push: `npm run build` (raiz: compila o admin + typecheck do kiosk) e a suite SQL via `tests/run_local.sh`
- Aplicar migrações: `npx supabase db push` (pode exigir aprovação humana interativa)
- Regenerar tipos após alteração de schema: `npx supabase gen types typescript --linked`
- Gestor de pacotes: **npm** (o repo tem `package-lock.json`)

## Ciclo de trabalho git (obrigatório)

1. Arranque de qualquer trabalho: `git checkout main && git pull`.
2. Criar sempre uma branch nova: `git checkout -b <release>/<descricao-curta>` (ex.: `r2/checklist-schema`). **Nunca trabalhar diretamente em `main`.**
3. Commits por unidade lógica, mensagens em português europeu, prefixo da release (ex.: `R2:`).
4. **Sem atribuição de AI nos commits**: nenhum trailer `Co-Authored-By`, nenhuma linha "Generated with Claude Code". (Reforçado por `includeCoAuthoredBy: false` no settings.)
5. Fecho: gates verdes → `git push -u origin <branch>` → **parar**. O Pull Request, a revisão e o merge são humanos.
6. `git push` para `main` é proibido em qualquer circunstância.

## Regras de trabalho

- Português europeu em código, comentários, commits e respostas.
- Migrações: `supabase/migrations/YYYYMMDDHHMMSS_nome.sql`, timestamp posterior à última migração aplicada. Nunca editar uma migração já aplicada — sempre uma nova.
- Ficheiros sempre completos; nunca patches parciais deixados a meio.
- Erros nunca são engolidos: mostrar sempre o texto completo do erro, nunca só contagens (helper `lib/erros.tsx` no admin).
- Se a especificação de uma tarefa divergir da realidade do código: parar, reportar a divergência, não improvisar.

## Invariantes de segurança (violação = bloqueante)

1. O kiosk está confinado a picagem + preenchimento de checklists. Funções de RH/administração nunca aparecem no kiosk.
2. `trabalhador.pin` nunca é legível por roles de cliente; escrita só via RPC SECURITY DEFINER. O PIN nunca é recuperável após criação (display-once mascarado).
3. Toda a função SECURITY DEFINER tem `set search_path to ''` e escopa todas as queries por `empresa_id` (um definer ignora RLS).
4. `picagem` é append-only (trigger de imutabilidade). Correção = novo registo, nunca UPDATE/DELETE.
5. Qualquer lookup de picagem anterior exclui anuladas: `and not p.anulada`.
6. Grants explícitos em tabelas e views; nunca depender de default privileges.
7. Conversão hora-de-parede→UTC só via helper `paredeParaUTC` (`packages/core`, Europe/Lisbon, DST-aware); nunca `new Date().toISOString()` para horas de parede.
8. Nada de biometria nem reconhecimento facial — é compromisso contratual (DPA cl. 3) e pressuposto da AIPD; violá-lo reabre todo o quadro jurídico.
9. Vera e qualquer agente de AI do produto: números e limites legais só de fonte citada ou tabela de autoridade, nunca de memória de modelo; humano aprova sempre.
10. Retenções legais são relógios independentes e configuráveis (6 relógios — ver doc 12, mapa consolidado); nunca um schedule único nem valores cravados.
11. NIF/NISS/IBAN vivem apenas na tabela cifrada com role próprio; nunca expostos ao kiosk.

## Delegação a subagentes

- Exploração e pesquisa no repo (localizar ficheiros, inventários, "onde é usado X"): delega ao agente `explorador`.
- Toda a migração SQL nova passa pelo `revisor-sql` **antes** do `supabase db push`; violações bloqueantes travam a aplicação.
- Implementação de tarefas com especificação fechada (ex.: tarefas numeradas de um prompt): delega ao `executor`, uma tarefa de cada vez, com o texto completo da tarefa no prompt de delegação.
- A thread principal reserva-se para: planeamento, decisões de arquitetura, síntese e verificação final.
- Tarefas pequenas e pontuais (fix de poucas linhas, pergunta rápida): resolve na thread principal, sem delegar.
