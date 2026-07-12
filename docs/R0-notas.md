# R0 — Notas de execução (2026-07-12)

Execução do R0 (saneamento) de ponta a ponta: migrações, admin, kiosk, testes.
Gates cumpridos: `npm run build` (workspace admin) verde antes de cada commit;
suite SQL completa verde no fecho (8/8 ficheiros, via `tests/run_local.sh`).
**Nada foi enviado por push** — commits locais para revisão humana.

## O que foi feito

### Migrações (aplicadas com `npx supabase db push` e verificadas na BD real)
- `20260712150000_excluir_anuladas_validacao_sequencia.sql` (P1) — `sequencia_valida`
  e `iniciar_picagem` passam a excluir picagens anuladas. *(Ficheiro já existia no
  working tree com o conteúdo exato pedido — foi usado tal como estava.)*
- `20260712150100_grants_explicitos_recusadas_e_anon.sql` (P2) — grants explícitos
  em `picagem_recusada` (authenticated só SELECT; anon nada) e revogação total de
  anon em `trabalhador`. *(Idem: já existia com o conteúdo pedido.)*
- `20260712150200_pin_definer_fechar_escrita.sql` — `criar_colaborador`,
  `gerar_novo_pin` e `atualizar_colaborador` convertidas para SECURITY DEFINER
  (verificação interna `is_admin()` + escopo por empresa, já presente nos corpos);
  escrita direta da coluna `pin` fechada a `authenticated` (o privilégio vinha do
  grant de tabela do Sprint 0, pelo que foi feita a reestruturação prevista no
  ponto 4: revoke de tabela + grant por coluna em todas exceto `pin`).

Verificação read-only na BD real (projeto `xghfsudvpsgqkslobttj`), tudo confirmado:
corpos com `anulada`; `prosecdef=true` nas 3 funções; `picagem_recusada` com
authenticated=SELECT e anon sem nada; anon sem privilégios em `trabalhador`;
authenticated sem INSERT/UPDATE em `pin` (mantém nas restantes colunas).
`supabase gen types --linked` regenerado: **idêntico** ao existente (nenhuma
assinatura mudou), pelo que não houve alteração ao ficheiro de tipos.

### Admin
- Edição de colaborador reanexada (recuperada de `032097d^`, origem `3a91986`):
  tab **Informação** com o formulário completo (RPC `atualizar_colaborador`) e
  toggle ativar/desativar; tab **PIN / Picagem** com "Gerar novo PIN" —
  mostrado uma única vez, **mascarado por defeito** com botão Revelar e aviso,
  estado limpo ao mudar de tab (P4 + P9).
- `paredeParaUTC` movida para `packages/core/src/datas.ts` (novo módulo de
  runtime; `transpilePackages` adicionado ao next.config) e usada no
  `NovaPicagemModal`, que deixa de converter com `new Date().toISOString()` naïf (P5).
- Superfície de erros (P3): novo `apps/admin/lib/erros.tsx` (`mensagemErro` com
  mensagem+código+details+hint; componente `ErroAviso`). Aplicado nos 9 sítios
  identificados no levantamento; a guarda de sessão passa o motivo para
  `/login?erro=...` e o login mostra-o. `setErro(error.message)` uniformizado
  para `mensagemErro` nos ficheiros tocados.

### Kiosk (P6)
- Itens online passam a guardar `trabalhador_id`/`codigo_pessoal` na outbox;
  `reportarRecusas` deixou de filtrar `origem='offline'` — recusas terminais de
  qualquer origem são reportadas via `reportar_picagem_recusada` e a linha local
  é apagada quando o servidor aceita (o servidor é a fonte de verdade; o badge
  vermelho deixa de ser perpétuo). Opção escolhida na tarefa 7.2: **limpar após
  confirmação de reporte** — sem perda de informação, sem ecrã novo no kiosk
  (mantém o confinamento).

### Testes (P7)
- `tests/06` e `tests/08` reescritos para o fluxo atual (bilhete + idempotência
  + sequência), com `begin/rollback`.
- Novo `tests/07_sequencia_anuladas_test.sql` (P1): anular → `sequencia_valida`
  ignora a anulada, `iniciar_picagem` não a devolve, novo registo aceite fim-a-fim.
- Novo `tests/run_local.sh`: suite completa num Postgres descartável (initdb em
  diretório temporário). Salta `20260628260000` (pg_cron) e `20260628340000`
  (pg_net) — extensões indisponíveis fora do Supabase; nada nos testes depende delas.
- Harness: `tests/00_local_bootstrap.sql` ganhou `auth.uid()`, `auth.sessions`,
  `raw_app_meta_data` e **pgcrypto no schema `extensions`** (fecha a falha
  conhecida do `extensions.hmac` num Postgres local); `tests/99` ganhou stub de
  `storage.filename()`.
- Resultado final: **8/8 ficheiros de teste passam**.

### Docs
- `docs/08-roadmap.md` §6: decisão emendada para **"PIN nunca recuperável após
  criação"** (antes "nunca é lido/nunca vê"), com a semântica display-once.

## Divergências registadas (regra 7)

1. **`docs/09-pendentes-e-roadmap-lancamento.md` não existe no repo** (em `docs/`
   há apenas `08-roadmap.md`, `09-levantamento-20260712.md` e `sprint1.md`).
   A tarefa 10.1 ("marcar P1–P9 como fechados" nesse doc) não pôde ser executada;
   o estado de fecho fica registado NESTAS notas: **P1–P9 executados** (P9 fechado
   pelo display-once mascarado da tarefa 5.2). Quando o doc for adicionado ao
   repo, marcar lá os pendentes.
2. **Tarefa 5.3 (navegação) já estava satisfeita**: o Início não duplica a lista
   de Colaboradores (é um dashboard de contagens com links) e não há links mortos
   — a ficha `/colaboradores/[id]` existe e a lista liga-lhe. O doc 08 §3
   descrevia um estado anterior ao commit `032097d`. Nada foi alterado na navegação.
3. **Raiz sem script `build`**: o gate `npm run build` foi corrido no workspace
   `admin` (`npm run build --workspace admin`); o kiosk (Expo, sem build) foi
   validado com `tsc --noEmit`.
4. **Testes 03/04/05 desatualizados face ao schema atual** (fora do âmbito 06/08,
   mas a suite tinha de ficar verde): o 03 afirmava o modelo do Sprint 2 (admin
   escreve `pin` por query direta; kiosk lê `pin`) — impossível desde
   `20260627120000` (leitura) e agora também na escrita (R0). Atualizados ao
   modelo atual, com as operações de setup/inspeção do PIN como superuser; o 05
   ganhou reposição da pré-condição (o 03 corrigido passa a criar o detalhe da Ana).
5. **Timestamps naïfs restantes no admin** (fora do âmbito da tarefa 6, que é
   picagem manual): filtros de listagem em `registos/page.tsx:87-88` e janela de
   export/normalização xlsx em `validacoes.tsx` — assumem browser em
   Europe/Lisbon apenas para filtrar/exportar, não criam picagens. Fica como
   dívida menor.

## Dívida registada (tarefa 9.3 — sem testes novos além do P1)

Continuam **sem teste SQL dedicado**: cache de PIN no servidor
(`obter_cache_pins`/`registar_chave_kiosk`), `registar_picagem_offline`,
recusas (`reportar_picagem_recusada`/`aceitar_recusa`/`descartar_recusa`),
revogação/terminar sessão de kiosk, imutabilidade (triggers), `corrigir_picagem`
/`anular_picagem`/`corrigir_picagem_bloco`/`aplicar_correcoes`/`aplicar_folha`,
retenção de fotos (esta última nem corre localmente — pg_cron/pg_net saltadas
pelo runner).

## Commits (por ordem)

1. `7397d44` — R0: migrações P1+P2+PIN (anuladas, grants explícitos, definer)
2. `a733bb3` — R0: reanexar edição de colaborador e corrigir navegação
3. `b759612` — R0: paredeParaUTC em packages/core, NovaPicagemModal DST-aware
4. `ad1762f` — R0: kiosk limpa recusas terminais reportadas
5. `b542e01` — R0: superfície de erros uniforme no admin
6. `611865a` — R0: testes 06/08 corrigidos + teste de anuladas + runner local
7. *(este)* — R0: fecho — notas de execução e emenda da decisão do PIN no doc 08
