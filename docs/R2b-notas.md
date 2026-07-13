# R2b — notas de fecho (2026-07-13)

> Fase R2b do doc 13: motor de conformidade no servidor, RPC atómica de
> preenchimento, fluxo de preenchimento no kiosk (online-only, D5) com ação
> corretiva forçada, e prova visível no admin.
> Branch `r2b/motor-conformidade-kiosk`; PR e merge humanos.
> Estrutura conforme o relatório de fecho obrigatório do CLAUDE.md.

## 1. Feito

1. **Migração `20260713210000_motor_conformidade_kiosk.sql`** (`edb732b`) —
   `avaliar_conformidade` (função pura, os 4 braços do doc 13 §3, parse
   defensivo → "valor ilegível", interna: EXECUTE revogado também de
   `authenticated`); `obter_checklists_kiosk` (SECURITY DEFINER, guards
   `is_kiosk()`+`kiosk_ativo()`, templates publicados aplicáveis à loja com
   itens ordenados — o kiosk continua sem SELECT direto em `checklist_*`);
   `registar_checklist` (SECURITY DEFINER atómica: PIN server-side, versão
   publicada aplicável à loja, reavaliação de TODAS as respostas no servidor,
   regra dura da ação corretiva com relatório completo de erros no padrão da
   `publicar_versao`, verificacao com contrato de foto da picagem, instância
   `concluida` com `versao_id` congelada e `due_at=null`, respostas com
   `conforme` do servidor, ações ligadas à mesma verificacao, notificação
   `email`/`pendente` por não conforme na mesma transação). Revista pelo
   `revisor-sql` antes de qualquer aplicação: sem bloqueantes; a NOTA dos
   duplicados foi corrigida (ação duplicada → erro no relatório).
2. **Motor partilhado + kiosk** (`40cddbc`) —
   `packages/core/src/conformidade.ts`: porta fiel dos 4 braços para avaliação
   local imediata (UX apenas; autoridade é o servidor) +
   `normalizarValorNumerico` (vírgula→ponto: cliente e servidor avaliam o
   mesmo valor canónico). Kiosk: secção "Checklists" ao lado da picagem —
   lista via `obter_checklists_kiosk` com cache leve SQLite (padrão da cache
   de PINs, TTL 1 h), autenticação código+PIN+foto de atribuição no padrão da
   picagem, formulário por tipo (numérico com unidade e limites visíveis,
   booleano com dois botões, texto livre), avaliação local imediata com campo
   de ação corretiva inline obrigatório antes do submit, online-only honesto
   ("Checklists indisponíveis sem ligação", sem outbox), erro do servidor
   mostrado por inteiro, upload da foto para o `foto_path` devolvido.
   Tipos provisórios das RPCs novas inseridos em `database.types.ts`
   (gerados via pg local + postgres-meta — procedimento do R2a).
3. **Admin — prova visível** (`aed6d40`) — tab "Preenchimentos" na secção
   Checklists (instâncias concluídas: template, loja, quem, quando, badge de
   não conformes) e detalhe de instância (versão, momentos dispositivo/
   servidor, foto de atribuição por signed URL enquanto viva com placeholder
   quando purgada, respostas na ordem dos itens com valor+unidade,
   conforme/não conforme, ação corretiva associada). Todos os embeds de FK
   composta pelo nome da constraint (padrão do R2a).
4. **Testes** (`3c7ccb1`) — `tests/12_motor_conformidade_test.sql`, 22 testes:
   os 4 braços com casos limite (ilegível, `booleano_conforme=false`, limite
   null de um lado, texto obrigatório vazio); `registar_checklist` (feliz,
   NC com/sem ação, `conforme` forjado ignorado, obrigatório em falta,
   rascunho rejeitado, kiosk de outra loja rejeitado, PIN errado, relatório
   acumulado com dois problemas, admin bloqueado); imutabilidade pós-fecho
   (UPDATE/DELETE bloqueados pelo trigger, testado como superuser para provar
   o trigger e não os grants); `obter_checklists_kiosk` (aplicáveis com itens
   ordenados, admin bloqueado, RLS nega leitura direta ao kiosk).
5. **Docs** (este commit) — doc 09 atualizado (R2b código fechado, R2c atual)
   e estas notas.

## 2. Não feito / pendente

- ~~**`npx supabase db push`**~~ — inicialmente travado pelo classificador
  (o gate de aprovação humana a funcionar); **aprovado pelo fundador e
  aplicado em 2026-07-14**. Verificação `verificador-bd` na BD real:
  **10/10 conformes** (assinaturas, prosecdef+search_path, grants incluindo
  anon/authenticated, guards, 4 braços do motor, erros acumulados,
  zero policies de kiosk, triggers intactos, zero instâncias). Tipos
  regenerados com `--linked`: idênticos aos provisórios (diff vazio).
  Nota: o push emitiu um erro colateral do `pg-delta` (certificado
  `pgdelta-target-ca.crt` em falta) que não impediu a aplicação —
  confirmado por `migration list` e pela verificação.
- **Idempotência do `registar_checklist`** (`p_chave_idempotencia`) — NOTA do
  revisor-sql; rede instável pode duplicar um preenchimento on-demand.
  Entra no R2c.
- **Envio das notificações** — aqui só o registo (`pendente`); worker/Resend
  é R2c. `destinatario` fica `null` (ver divergências).
- **Captura de foto por item no kiosk** — a biblioteca base não tem nenhum
  item `tipo_resposta='foto'` (confirmado na Tarefa 1: 18 numéricos + 19
  booleanos), portanto ficou FORA do R2b conforme o âmbito do prompt. O motor
  suporta o braço 4 (testado); quando existirem itens foto, falta só a UI de
  captura por item.
- **Agendador, instâncias `pendente`/`em_falta`** — R2c (fora de âmbito).

## 3. Erros encontrados

1. **Revisor-sql (NOTA): ações corretivas duplicadas aceites em silêncio** —
   duas entradas em `p_acoes` para o mesmo item criavam duas `acao_corretiva`.
   Causa: o loop de validação desduplicava sem acusar. Correção: duplicado
   passa a erro no relatório acumulado (mesma migração, antes de aplicada).
2. **Erro de upload da foto engolido no kiosk** — a primeira implementação
   registava a falha de upload só em `console.warn`, violando "erros nunca
   são engolidos". Correção: estado `avisoFoto` mostrado no ecrã de sucesso
   ("o registo foi guardado, mas a foto não foi carregada: <erro completo>"),
   sem abortar (o registo já persistiu; retry criaria duplicados sem
   idempotência).
3. **Conflito interno de decisões na migração** — a primeira versão omitia
   `foto_url` na `verificacao`, mas a Tarefa 4.2 exige a foto de atribuição
   na prova do admin e a Tarefa 3.2 manda seguir o padrão da picagem.
   Corrigido antes de aplicar: contrato igual ao da `registar_picagem`
   (servidor gera id, grava o caminho, devolve `foto_path`; a policy do
   bucket `picagens` já cobre o caminho).

## 4. Divergências (spec vs realidade)

1. **Nome da RPC — RESOLVIDA em 2026-07-14**: doc 13 §3 dizia
   `registar_respostas_checklist`; o fundador fixou `registar_checklist`
   como nome final e o doc 13 foi alinhado nesta branch.
2. **`momento_dispositivo` como parâmetro explícito** da RPC (o prompt
   listava-o "no payload"): seguiu-se o padrão da `registar_picagem`.
3. **`notificacao.destinatario` = null**: a coluna é nullable e não existe
   fonte configurável de destinatário por loja no R2b; o worker R2c resolve o
   destino. Registado também no cabeçalho da migração.
4. **Não há primitivo reutilizável `criar_verificacao`**: a picagem insere a
   `verificacao` inline; a RPC nova replica o mesmo INSERT (mesmas colunas e
   contrato) em vez de inventar um helper novo.
5. **Grants de UPDATE/DELETE ausentes em `checklist_resposta`/
   `acao_corretiva`** para `authenticated`: o erro de imutabilidade chega
   primeiro por `insufficient_privilege` e só depois (superuser) pelo trigger.
   É defesa em profundidade — mantido; os testes 18–19 provam o trigger como
   superuser.
6. **Doc 04/biblioteca sem itens `texto` nem `foto`**: o formulário e o motor
   suportam os 4 tipos na mesma (doc 13 §2.4 permite-os em templates novos).

## 5. O que NÃO foi alterado

- O fluxo de picagem do kiosk (`PicagemScreen.tsx`, `lib/outbox.ts`,
  `lib/cache-pin.ts`): zero alterações; `App.tsx` só ganhou a navegação.
- O construtor de templates no admin (R2a) e as suas rotas.
- Todas as migrações existentes (a nova é aditiva: só `create function`
  + grants; nenhuma tabela, policy ou trigger alterados).
- `supabase/seed.sql`, testes 01–11 (intocados; a suite inteira passa).
- Nada de offline/outbox para checklists (D5 fechada no doc 13).

## 6. Decisões que precisam de validação humana

1. Nome `registar_checklist` vs doc 13 (`registar_respostas_checklist`).
2. Foto de atribuição também no preenchimento de checklists (mesmo contrato
   e bucket da picagem) — coerente com a AIPD atual? (é o mesmo tratamento
   já documentado para a picagem, mas o fim é novo: prova HACCP.)
3. `destinatario=null` nas notificações até ao R2c.
4. UX do teclado numérico como painel inferior fixo (adaptação do Keypad da
   picagem a formulário multi-item).
5. Itens booleanos NÃO obrigatórios sem seleção ficam fora do payload (o
   servidor avaliá-los-ia como "valor ilegível" → não conforme sem forma de
   o colaborador introduzir ação na UI).

## 7. Gates

- `npm run build` (raiz): verde — admin compila + typecheck do kiosk sem erros.
- `tests/run_local.sh`: verde — 12 ficheiros de teste, incluindo os 22 novos;
  "SUITE: todos os testes passaram".
- Verificação da BD real (`verificador-bd`, pós-push 2026-07-14):
  **10/10 conformes**.

## 8. Próximo passo do humano

Rever e fazer merge do PR (criado com confirmação explícita do fundador em
2026-07-14, após push aprovado e verificação 10/10). As divergências 3 e 5
da secção 4 ficaram aceites como estão (decisão do fundador); a idempotência
e o `destinatario` seguem para o R2c via doc 09.
