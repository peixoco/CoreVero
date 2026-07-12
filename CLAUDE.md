# CoreVero — memória de projeto

SaaS multi-tenant (isolamento por `empresa_id` + RLS) para restauração em Portugal: relógio de ponto autenticado (Frente A, completa) + HACCP configurável (Frente B, a seguir). Fundador solo. A fonte de verdade de arquitetura, roadmap e decisões são os docs numerados em `docs/` (00–10); o estado real do código está em `docs/09-levantamento-*.md`.

## Estrutura

- `apps/admin` — Next.js 16 App Router (painel do gestor)
- `apps/kiosk` — Expo SDK 56 (tablet partilhado, sessão permanente)
- `packages/core` — código partilhado (tipos, helpers)
- `supabase/migrations` — migrações SQL (Postgres 17, projeto eu-west-3)

## Comandos

- Gate obrigatório antes de qualquer commit: `npm run build` na raiz (build do admin + typecheck do kiosk)
- Aplicar migrações: `npx supabase db push`
- Regenerar tipos após alteração de schema: `npx supabase gen types typescript --linked`

## Regras de trabalho

- Português europeu em código, comentários, commits e respostas.
- Branch única: `main`.
- Migrações: `supabase/migrations/YYYYMMDDHHMMSS_nome.sql`. Nunca editar uma migração já aplicada — sempre uma nova.
- Ficheiros sempre completos; nunca patches parciais deixados a meio.
- Erros nunca são engolidos: mostrar sempre o texto completo do erro, nunca só contagens.
- Se a especificação de uma tarefa divergir da realidade do código: parar, reportar a divergência, não improvisar.

## Invariantes de segurança (violação = bloqueante)

1. O kiosk está confinado a picagem + preenchimento de checklists. Funções de RH/administração nunca aparecem no kiosk.
2. `trabalhador.pin` nunca é legível por roles de cliente; escrita só via RPC SECURITY DEFINER. O PIN só é visível uma única vez, na criação/regeneração.
3. Toda a função SECURITY DEFINER tem `set search_path to ''` e escopa todas as queries por `empresa_id` (um definer ignora RLS).
4. `picagem` é append-only (trigger de imutabilidade). Correção = novo registo, nunca UPDATE/DELETE.
5. Qualquer lookup de picagem anterior exclui anuladas: `and not p.anulada`.
6. Grants explícitos em tabelas e views; nunca depender de default privileges.
7. Conversão hora-de-parede→UTC só via helper `paredeParaUTC` (Europe/Lisbon, DST-aware); nunca `new Date().toISOString()` para horas de parede.
8. Nada de biometria. NIF/NISS/IBAN vivem apenas na tabela cifrada com role próprio; nunca expostos ao kiosk.
9. Vera e qualquer agente de AI do produto: números e limites legais só de fonte citada ou tabela de autoridade, nunca de memória de modelo; humano aprova sempre.
10. Retenções legais (RGPD, laboral 5 anos, fiscal 10 anos, HACCP) são relógios independentes e configuráveis — nunca um schedule único nem valores cravados.

## Delegação a subagentes

- Exploração e pesquisa no repo (localizar ficheiros, inventários, "onde é usado X"): delega ao agente `explorador`.
- Toda a migração SQL nova passa pelo `revisor-sql` **antes** do `supabase db push`; violações bloqueantes travam a aplicação.
- Implementação de tarefas com especificação fechada (ex.: tarefas numeradas de um prompt): delega ao `executor`, uma tarefa de cada vez, com o texto completo da tarefa no prompt de delegação.
- A thread principal reserva-se para: planeamento, decisões de arquitetura, síntese e verificação final.
- Tarefas pequenas e pontuais (fix de poucas linhas, pergunta rápida): resolve na thread principal, sem delegar.
