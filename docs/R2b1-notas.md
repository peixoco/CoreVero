# R2b1 — correções do teste de cozinha (notas de fecho)

Branch: `r2b1/correcoes-teste-cozinha` · Base: `main` (49a080a, pós-merge do R2b)

**Decisão de produto (fundador, reverte parte do R2b):** a autenticação de
checklists passa a ser só **código + PIN**, sem foto de atribuição. A foto de
atribuição é exclusiva da picagem (anti-fraude do registo de tempos, auditoria
aleatória; minimização RGPD). Fotos em checklists existem apenas ao nível do
item (`tipo_resposta='foto'`, câmara traseira) — pendente para R2c+.

## 1. Feito

| Commit | Conteúdo |
|---|---|
| 63aa801 | Doc 13, emenda ao §3 (fluxo `registar_checklist`): verificação nasce sem foto (`foto_url null`); nota da decisão do fundador. |
| f6bad8b | Migração `20260714120000_registar_checklist_sem_foto.sql` (`create or replace`, assinatura inalterada; resumo sem `foto_path`) + testes: TESTE 8 exige `foto_url null` e ausência de `foto_path`; TESTE 3 com fronteira −18 conforme e −17.5 não conforme. |
| b616f68 | Kiosk: fluxo código + PIN → formulário (câmara/upload removidos); botão ± no teclado numérico; tempo-limite de 20 s no submit; `normalizarValorNumerico` aceita negativos (menos Unicode → ASCII, trim). |
| 1c2532a | Admin (Preenchimentos): em erro, a lista mostra o erro completo em vez de ficar presa em «A carregar…»; detalhe indica «registo autenticado por código + PIN» quando não há foto (instâncias antigas mantêm a foto enquanto viver). |

## 2. Não feito / pendente

- Fotos ao nível do item no kiosk (câmara traseira) — R2c+, por decisão.
- Idempotência do `registar_checklist` — continua para R2c (nota herdada do R2b).
- Reteste do bug 6 (tab Preenchimentos) pelo fundador — ver §4.

## 3. Erros encontrados

- **Spinner infinito pós-submit:** a única `await` entre o sucesso do RPC e o
  ecrã de confirmação era o upload da foto de atribuição; além disso o `fetch`
  do React Native não tem timeout — uma resposta perdida deixava a promise
  pendurada para sempre. Correção: bloco de upload removido (deixa de existir)
  + tempo-limite de 20 s no RPC com mensagem explícita de que o registo pode
  ter persistido.
- **Typecheck:** o builder do supabase-js é `PromiseLike`, não `Promise` —
  assinatura do helper `comTempoLimite` ajustada.
- **verificador-bd a «ver» BD vazia:** o role de `$VERIFICA_DB_URL` é
  read-only e não é `authenticated` → RLS filtra TODOS os dados de tabelas de
  domínio (contagens dão 0 na BD certa). Consultas de catálogo não são
  afetadas. Consequência operacional: o verificador só prova schema/funções/
  grants/policies; contraprovas de DADOS fazem-se no Studio. O sanity check da
  ligação passa a ser a presença da última migração em
  `supabase_migrations.schema_migrations`.

## 4. Divergências

- A tarefa referia «§3.2» do doc 13; o doc não tem subsecções no §3 — a emenda
  entrou no ponto 2 de «Autoridade e fluxo» (§3), onde o fluxo está descrito.
- **Bug 6 (tab Preenchimentos vazia) não reproduzível na camada de dados:**
  reprodução completa local (Postgres descartável + migrações + seed + registo
  via RPC como kiosk + leitura como admin com RLS ativa) mostra a instância e
  todos os embeds; a sintaxe dos embeds por constraint foi validada contra o
  PostgREST real (resolve; erro devolvido é só o 42501 esperado do anon). O
  código foi endurecido para o erro nunca ficar mascarado pelo loading.
  **Se o sintoma voltar:** com erro visível → a mensagem identifica a camada;
  vazio sem erro → causa de dados/sessão (ex.: empresa do gestor ≠ empresa da
  instância), a confirmar no Studio.
- Snapshot git inicial mostrava uma branch homónima com alterações não
  commitadas; no arranque real a árvore estava limpa e a branch não existia —
  nada foi perdido nem sobreposto.

## 5. O que NÃO foi alterado

Fluxo de picagem (câmara frontal, outbox, upload — zero ficheiros tocados);
`avaliar_conformidade` (SQL e porta TS — já aceitavam negativos);
`obter_checklists_kiosk`; schema de tabelas (nenhum DDL de colunas);
policies/grants; cache de checklists do kiosk; página de Templates do admin.

## 6. Decisões que precisam de validação humana

- Tempo-limite de 20 s e texto da mensagem de timeout no kiosk.
- Botão ± junto ao visor do teclado numérico (não em cada cartão de item).
- Rótulo do botão pós-PIN: «Preencher» (antes «Avançar», que levava à câmara).
- Aceitar o reteste como fecho do bug 6 (ver §4).

## 7. Gates

- `npm run build`: admin compila + typecheck do kiosk limpo ✓
- `tests/run_local.sh`: `SUITE: todos os testes passaram` (22 testes do motor,
  incl. fronteiras −18 e caminho feliz sem foto) ✓
- revisor-sql: **APROVADA** — zero violações bloqueantes; diff semântico
  confirma só as duas alterações previstas ✓
- BD real (pós-push, catálogo): migração registada; função remota sem
  `v_foto_path`/`.jpg`, insert com `null`; `security definer` + `search_path`
  vazio; EXECUTE só de `authenticated`/`service_role`; `avaliar_conformidade`
  intacta — conforme (único ⚠: «foto_path» surge num comentário da função) ✓

## 8. Próximo passo do humano

Rever o PR (se criado), retestar na cozinha: checklist só com código + PIN,
valor −18 pelo ±, fecho no ecrã de confirmação, e a tab Preenchimentos no
admin (agora com erro visível se algo falhar).
