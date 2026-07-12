# 09 — Levantamento do estado atual (2026-07-12)

> Levantamento estritamente read-only do monorepo (apps/admin Next.js 16, apps/kiosk Expo SDK 56, packages/core, supabase/migrations). Toda a evidência é do repositório; o que só se confirma na base de dados real está marcado `[a verificar na BD]`. Exceção: os privilégios de `picagem_recusada` foram confirmados na BD real (projeto `xghfsudvpsgqkslobttj`) por consulta read-only via MCP.

## 1. Resumo executivo (10 linhas máx.)

A captura de picagem está completa e sólida: online (PIN server-side + bilhete), offline (outbox SQLite, cache HMAC 7 dias, re-validação no drain), idempotência, recusas expostas ao admin, 4 tipos incluindo pausas. A Frente A está muito mais avançada do que o doc 08 afirma: cálculo de horas, validação de sequência, imutabilidade (triggers append-only), correções (unitária/bloco/xlsx/folha) e retenção de fotos via pg_cron já existem. As 18 tabelas têm todas RLS. Frentes B (HACCP) e C (RH) não começaram. Os defeitos que importam: `sequencia_valida` e `iniciar_picagem` **não excluem picagens anuladas** (divergência online/offline confirmada, produz recusas erradas no drain); o admin **engole erros em 9 sítios** (KPIs mostram 0 em falha); a decisão fechada "PIN nunca é lido" está **violada na UI de criação**; a edição de colaborador **foi regredida** (RPCs `atualizar_colaborador`/`gerar_novo_pin` órfãs); os testes SQL de `registar_picagem` estão obsoletos e nada da fase 2+ tem teste. O doc 08 e o SETUP.md estão desatualizados face ao código. Os docs 00–07 referenciados não existem no repo.

## 2. Feito e funcional

### Base de dados (31 migrações, `supabase/migrations/`)

Cronologia (uma linha por migração):

| Migração | O que faz |
|---|---|
| `20260625090000_schema.sql` | Esquema inicial multi-tenant: empresa, loja, trabalhador, trabalhador_loja, verificacao, picagem, checklists HACCP (template/_loja/item/instancia/resposta, acao_corretiva), notificacao, utilizador_app; FKs compostas (empresa_id, id). |
| `20260625090100_rls.sql` | `empresa_atual()` (claim JWT), grants a authenticated, RLS em todas as tabelas com policy uniforme `tenant_isolation`. |
| `20260626100000_identidade_acesso.sql` | Helpers `jwt_app_meta`/`loja_atual`/`is_admin`/`is_kiosk`; substitui `tenant_isolation` por `admin_empresa` + policies finas de kiosk (insert-only + leitura fina). |
| `20260626110000_colaborador_detalhe.sql` | Colunas `pin` (CHECK 4 dígitos) e `area` em trabalhador; tabela `trabalhador_detalhe` (RH 1:1, só admin). |
| `20260626120000_picagem_intervalos.sql` | CHECK de `picagem.tipo` passa a 4 tipos (`entrada`/`saida`/`inicio_intervalo`/`fim_intervalo`). |
| `20260626130000_criar_colaborador.sql` | RPCs `criar_colaborador` (gera código sequencial ≥1001 + PIN) e `gerar_novo_pin` (SECURITY INVOKER). |
| `20260627100000_atualizar_colaborador.sql` | RPC `atualizar_colaborador` (update trabalhador + upsert detalhe, só admin). |
| `20260627110000_registar_picagem.sql` | 1.ª `registar_picagem` (DEFINER), bucket privado `picagens` + policies de storage. |
| `20260627120000_pin_credencial.sql` | PIN como credencial: revoke SELECT de tabela em trabalhador + grant coluna-a-coluna sem `pin`. |
| `20260627130000_vista_picagem.sql` | View `vista_picagem` (security_invoker=true) para listagem/exports, sem expor `pin`. |
| `20260628120000_picagem_fase2.sql` | Fluxo 2 passos anti-foto-órfã: `iniciar_picagem` + `registar_picagem` com id do servidor; helper `verificacao_pertence_kiosk`. |
| `20260628140000_foto_por_trabalhador.sql` | Caminho da foto `{empresa}/{loja}/{trabalhador}/{verificacao}.jpg`; helper `verificacao_do_trabalhador`; policy de upload endurecida. |
| `20260628160000_idempotencia_picagem.sql` | `verificacao.chave_idempotencia` + índice único parcial; `registar_picagem` idempotente. |
| `20260628180000_autorizacao_bilhete.sql` | Tabela `autorizacao` (bilhete de uso único, 6h); `iniciar_picagem` emite, `registar_picagem` consome (sem PIN). |
| `20260628200000_revogar_kiosk.sql` | Tabela `kiosk` + `kiosk_ativo()`; RPCs `revogar_kiosk`/`reativar_kiosk`; guard nas RPCs e na policy de upload. |
| `20260628220000_cache_pin_servidor.sql` | `kiosk.chave_hmac`; RPCs `registar_chave_kiosk` e `obter_cache_pins` (HMAC-SHA256, nunca o PIN em claro). |
| `20260628230000_picagem_offline.sql` | `verificacao.autorizacao_offline`; RPC `registar_picagem_offline` (re-valida no drain). |
| `20260628240000_picagem_recusada.sql` | Tabela `picagem_recusada` (só SELECT para admin) + RPC `reportar_picagem_recusada` (funciona mesmo revogado). |
| `20260628250000_terminar_sessao_kiosk.sql` | RPC `terminar_sessao_kiosk` v1 (corrigida em 270000). |
| `20260628260000_limpar_autorizacoes.sql` | Extensão pg_cron; job diário 03:00 `limpar-autorizacoes` (bilhetes usados/expirados >1 dia). |
| `20260628270000_terminar_sessao_so_sessao.sql` | `terminar_sessao_kiosk` só apaga sessão Auth; não toca em `ativo` (eixos separados). |
| `20260628280000_gerir_recusas.sql` | Estado de resolução em `picagem_recusada`; `verificacao.correcao_manual`/`criada_por`; RPCs `descartar_recusa`/`aceitar_recusa`. |
| `20260628290000_validacao_sequencia.sql` | Helper `sequencia_valida` (máquina de transições, dia de Lisboa); imposta em `registar_picagem` e `registar_picagem_offline`. |
| `20260628300000_vista_horas_dia.sql` | View `vista_horas_dia` (security_invoker=true): horas trabalho/pausa por trabalhador-dia, flags incompleto/todos_fechados. |
| `20260628310000_imutabilidade_correcoes.sql` | Colunas de anulação; triggers append-only em verificacao/picagem; revoke update/delete; RPCs `corrigir_picagem`/`anular_picagem`; views recriadas (horas exclui anuladas). |
| `20260628320000_aplicar_correcoes.sql` | RPC `aplicar_correcoes(jsonb)`: correções em massa (xlsx), erro por linha não derruba o lote. |
| `20260628330000_aplicar_folha.sql` | RPC `aplicar_folha(jsonb, p_simular)`: reconciliação de folha de horas com pré-visualização. |
| `20260628340000_retencao_foto.sql` | pg_net; `empresa.retencao_foto_dias` (30); `purgar_fotos_expiradas()` (Storage via pg_net + Vault); job pg_cron 03:30 `purgar-fotos`. |
| `20260628360000_cache_ultimo_estado.sql` | `obter_cache_pins` passa a devolver `ultimo_tipo`/`ultimo_momento` (não-anulada) para opções válidas offline. |
| `20260629120000_corrigir_picagem_bloco.sql` | RPC `corrigir_picagem_bloco` (datas × trabalhadores × movimentos, pré-flight de sequência que exclui anuladas, p_simular). |
| `20260629130000_fix_corrigir_picagem_loja_unica.sql` | Fix do fallback de loja única em `corrigir_picagem` (bug `min(uuid)`). |

Nota: não existe `20260628350000` — salto de numeração, sem ficheiro em falta.

**Inventário (estado final):**
- **Tabelas: 18, todas com RLS ativado e pelo menos uma policy** — empresa, loja, trabalhador, trabalhador_loja, verificacao, picagem, checklist_template, checklist_template_loja, checklist_item, checklist_instancia, checklist_resposta, acao_corretiva, notificacao, utilizador_app, trabalhador_detalhe, autorizacao, kiosk, picagem_recusada. **Tabelas sem RLS: nenhuma** (verificado adversarialmente; zero `disable row level security`).
- **Views (2, ambas `security_invoker=true`)**: `vista_picagem` (versão final em `20260628310000:192`, expõe anulada/motivo/correcao_manual) e `vista_horas_dia` (final em `20260628310000:156`, exclui anuladas em `:164`).
- **Triggers (2)**: `trg_imutavel_verificacao` (`20260628310000:53-55`, só `foto_url` alterável) e `trg_imutavel_picagem` (`20260628310000:74-76`, só colunas `anulada*`).
- **Jobs pg_cron (2)**: `limpar-autorizacoes` (0 3 * * *, `20260628260000:38-42`) e `purgar-fotos` (30 3 * * *, `20260628340000:83`, usa pg_net + segredo Vault). Agendamento na BD real: `[a verificar na BD]`.
- **RPCs SECURITY DEFINER (18)**: iniciar_picagem, registar_picagem, registar_picagem_offline, kiosk_ativo, revogar_kiosk, reativar_kiosk, registar_chave_kiosk, obter_cache_pins, reportar_picagem_recusada, terminar_sessao_kiosk, limpar_autorizacoes, descartar_recusa, aceitar_recusa, sequencia_valida, corrigir_picagem, anular_picagem, aplicar_correcoes, aplicar_folha, purgar_fotos_expiradas, verificacao_pertence_kiosk, verificacao_do_trabalhador. **SECURITY INVOKER**: criar_colaborador, gerar_novo_pin, atualizar_colaborador, helpers de identidade, funções-trigger.
- **Verificações pedidas**: contagem de recusadas no dashboard **filtra `estado='pendente'`** ([page.tsx:27-31](apps/admin/app/(painel)/page.tsx#L27-L31), confirmado); CHECK final de `picagem.tipo` **aceita exatamente os 4 tipos** (`20260626120000:22-23`, confirmado; RPCs validam inline os mesmos 4); **PIN revogado ao authenticated** — revoke de tabela + grant por coluna sem `pin` (`20260627120000:8-13`), nenhuma migração posterior re-concede, `trabalhador.pin` é a única coluna de PIN do schema (confirmado). `sequencia_valida` vs anuladas: **não exclui** — ver secção 3.

### App admin (`apps/admin`)

| Rota | Estado | Nota |
|---|---|---|
| `/` (Início) | Funcional | 3 KPIs reais (contagens head-only) + 3 cartões "Em breve" declarados. |
| `/login` | Funcional | signInWithPassword, erro mostrado. |
| `/colaboradores` | Funcional | Lista + link para ficha + "+ Novo"; erro do select mostrado. |
| `/colaboradores/novo` | Funcional | RPC `criar_colaborador`; mostra código+PIN (ver secções 3 e 6). |
| `/colaboradores/[id]` | Parcial | Só a tab "PIN / Picagem" é funcional (ver secção 4). |
| `/registos` | Funcional | Tabs Picagens (filtros, recusas, modais Nova/Bloco) e Validações (folha xlsx); Checklists é placeholder. |
| `/definicoes` | Funcional | Conta · Lojas · Dispositivos (revogar/reativar/terminar sessão, confirmação por nome). |
| `/picagens` | Casca | Só `redirect("/registos")` ([picagens/page.tsx:4](apps/admin/app/(painel)/picagens/page.tsx#L4)). |

Navegação: **o Início NÃO duplica a lista de Colaboradores** (só contagem head-only + Link, [page.tsx:15-19,41-45](apps/admin/app/(painel)/page.tsx#L15-L19)) e **não há links mortos** (grep exaustivo de href/router.push/redirect confirmado adversarialmente) — ambas as afirmações do doc 08:74 estão desatualizadas.

Componentes-chave: modal Nova Picagem ([registos/page.tsx:464-563](apps/admin/app/(painel)/registos/page.tsx#L464-L563)); Picagens em Bloco com simulação obrigatória antes de aplicar ([registos/page.tsx:577-828](apps/admin/app/(painel)/registos/page.tsx#L577-L828), horas de parede convertidas no SQL com `at time zone 'Europe/Lisbon'`); painel de recusas ([registos/page.tsx:264-317](apps/admin/app/(painel)/registos/page.tsx#L264-L317)); Validações/folha xlsx com pré-visualização ([validacoes.tsx:75-325](apps/admin/app/(painel)/registos/validacoes.tsx#L75-L325)).

### App kiosk (`apps/kiosk`)

- Máquina de estados `codigo → pin → tipo → camera → processar → sucesso/erro` ([PicagemScreen.tsx:100-107](apps/kiosk/PicagemScreen.tsx#L100-L107)); sessão persistida em AsyncStorage.
- **Online**: `iniciar_picagem` valida PIN e emite bilhete; captura com hora autoritária do toque e chave de idempotência; item enfileirado e ✓ mostrado quando durável localmente; drain regista + sobe foto.
- **Offline**: validação HMAC local ([cache-pin.ts:186-218](apps/kiosk/lib/cache-pin.ts#L186-L218)), mensagens diferenciadas (expirada/PIN errado/sem cache), UI honesta ("registada offline · por confirmar"), re-validação no drain via `registar_picagem_offline`; recusa terminal → reportada ao admin e limpa.
- **Outbox** ([outbox.ts](apps/kiosk/lib/outbox.ts)): SQLite, foto em base64 na própria linha (sem ficheiros geridos), `insert or ignore` idempotente, mutex anti-reentrância, linha só apagada **após upload confirmado** (ou 409 duplicado) — confirmado adversarialmente ([outbox.ts:304-313](apps/kiosk/lib/outbox.ts#L304-L313)); recusa terminal esvazia `foto_b64` imediatamente (minimização, [outbox.ts:260-262](apps/kiosk/lib/outbox.ts#L260-L262)).
- **Cache de PIN**: chave 32 bytes no Keychain (SecureStore), HMAC compatível byte-a-byte com `extensions.hmac` do servidor; **TTL = 7 dias exatos** ([cache-pin.ts:44](apps/kiosk/lib/cache-pin.ts#L44)), persistido em SQLite (sobrevive a reinícios); refresh substitui a cache inteira, throttled a 5 min. Não há TTL do lado servidor (não existe valor com que divergir — confirmado).
- **Indicador de pendentes: existe** — badge âmbar "N por enviar" + badge vermelho "N recusadas — contacte o gestor" ([PicagemScreen.tsx:356-377](apps/kiosk/PicagemScreen.tsx#L356-L377)), atualizados a cada 15 s e no regresso a foreground.
- **`opcoesPara()`** ([PicagemScreen.tsx:67-79](apps/kiosk/PicagemScreen.tsx#L67-L79)): última entrada/fim_intervalo → {inicio_intervalo, saida}; inicio_intervalo → {fim_intervalo}; saida/null → {entrada}. Semanticamente idêntica hoje à `sequencia_valida` do SQL — mas duplicada, não partilhada (ver secção 7).

### Partilhado (`packages/core`)

- Contém **apenas** os tipos gerados do Supabase (`database.types.ts`, 1272 linhas) re-exportados por `src/index.ts`. Zero funções/lógica de runtime.
- **Tipos atualizados** face às 31 migrações — verificado item a item (picagem_recusada + estado, kiosk.chave_hmac, autorizacao_offline, corrigir_picagem_bloco, obter_cache_pins final, vistas) e confirmado adversarialmente; regenerados no commit `b98f2fa` junto com as últimas migrações. Correspondência com a BD real: `[a verificar na BD]`.
- Consumo: **1 único import em todo o monorepo** ([apps/admin/lib/supabase.ts:2](apps/admin/lib/supabase.ts#L2)); o kiosk não usa tipos (cliente não tipado).

## 3. Feito mas com problemas conhecidos (com ficheiro:linha)

1. **`sequencia_valida` não exclui picagens anuladas** — `supabase/migrations/20260628290000_validacao_sequencia.sql:30-40` (WHERE sem filtro `anulada`; a coluna nasceu depois, em `20260628310000:24-28`, e a função nunca foi atualizada). Afeta `registar_picagem` (`:99`) e `registar_picagem_offline` (`:166`). O próprio repo reconhece: `20260629120000_corrigir_picagem_bloco.sql:21-23` ("Limitação conhecida… Fechar a divergência em sequencia_valida é um item à parte"). Confirmado adversarialmente.
2. **`iniciar_picagem` devolve a última picagem de hoje SEM excluir anuladas** (`20260628200000_revogar_kiosk.sql:177-187`) enquanto `obter_cache_pins` exclui (`20260628360000:51`). Cenário confirmado: entrada anulada pelo admin → online o kiosk oferece Saída/Pausa (dia parte-se no cálculo de horas); offline oferece Entrada, mas o drain recusa-a porque `sequencia_valida` ainda vê a anulada — **a via com a semântica correta é a penalizada com recusa**.
3. **Timestamp naïf no modal Nova Picagem** — [registos/page.tsx:485](apps/admin/app/(painel)/registos/page.tsx#L485) `new Date(momento).toISOString()` (assume browser em Europe/Lisbon, comentário na `:484`); o helper DST-aware `paredeParaUTC` existe mas só como função local em [colaboradores/[id]/page.tsx:48-53](apps/admin/app/(painel)/colaboradores/[id]/page.tsx#L48-L53) (não está em packages/core). Filtros de datas com o mesmo padrão naïf ([registos/page.tsx:85-86](apps/admin/app/(painel)/registos/page.tsx#L85-L86)). Os fluxos bloco/correções/folha convertem no SQL com `at time zone 'Europe/Lisbon'` — corretos.
4. **Erros de RPC/select engolidos no admin (9 locais)** — em falha mostram 0/nada sem aviso: KPIs do Início ([page.tsx:19](apps/admin/app/(painel)/page.tsx#L19), [:25](apps/admin/app/(painel)/page.tsx#L25), [:31](apps/admin/app/(painel)/page.tsx#L31) — o `:31` desativa o realce de alerta das recusas); painel de recusas ([registos/page.tsx:111-113](apps/admin/app/(painel)/registos/page.tsx#L111-L113)); dropdowns de colaboradores ([registos/page.tsx:122](apps/admin/app/(painel)/registos/page.tsx#L122), [validacoes.tsx:89-90](apps/admin/app/(painel)/registos/validacoes.tsx#L89-L90) — folha exportada sairia vazia); nome e horas da ficha ([colaboradores/[id]/page.tsx:77-78](apps/admin/app/(painel)/colaboradores/[id]/page.tsx#L77-L78), [:106](apps/admin/app/(painel)/colaboradores/[id]/page.tsx#L106)); guarda de sessão ([layout.tsx:25-29](apps/admin/app/(painel)/layout.tsx#L25-L29)). Onde o erro é mostrado, usa-se só `error.message` (omite `details`/`hint`/`code` do PostgREST).
5. **PIN mostrado em claro ao admin** — [colaboradores/novo/page.tsx:54,64-67](apps/admin/app/(painel)/colaboradores/novo/page.tsx#L54-L67) renderiza `{criado.pin}` em text-3xl; `criar_colaborador` e `gerar_novo_pin` devolvem o PIN em claro (`20260626130000:76`, `:83,:102`). Viola a decisão fechada docs/08-roadmap.md:113 (ver secção 6). Ao nível da BD a credencial está protegida (revoke por coluna).
6. **Recusas terminais de picagens ONLINE nunca são reportadas nem limpas no kiosk** — `reportarRecusas` filtra `origem='offline'` ([outbox.ts:335-336](apps/kiosk/lib/outbox.ts#L335-L336)); um bilhete expirado/sequência inválida online deixa o badge vermelho perpétuo e o admin nunca vê a recusa.
7. **Estado efetivo offline ignora picagens online por drenar** — `ultimoPickLocalHoje` filtra `origem='offline'` ([outbox.ts:182-184](apps/kiosk/lib/outbox.ts#L182-L184)); pode sugerir tipo que o servidor recusará no drain.
8. **Classificação de recusa terminal por regex sobre o texto da mensagem** ([outbox.ts:216-221](apps/kiosk/lib/outbox.ts#L216-L221)) — mudar a redação das exceções SQL converte recusas em retries infinitos ou vice-versa. `eErroDeRede` com ramo `|| !error.code` demasiado permissivo ([PicagemScreen.tsx:94-97](apps/kiosk/PicagemScreen.tsx#L94-L97)).
9. **Ficheiro temporário da câmara nunca apagado** — `takePictureAsync` grava no cache do SO e a app só consome o base64 ([PicagemScreen.tsx:306-309](apps/kiosk/PicagemScreen.tsx#L306-L309)); rostos ficam no cache do dispositivo por tempo indefinido, contrariando a minimização declarada em [outbox.ts:19](apps/kiosk/lib/outbox.ts#L19).
10. **Testes SQL de picagem obsoletos** — `tests/06_registar_picagem_test.sql:22-116` e `tests/08_vista_picagem_test.sql:13-15` chamam a assinatura de `registar_picagem` dropada em `20260628120000:117`; falham contra o schema atual e a versão final não tem teste.
11. **pgcrypto criada sem schema vs chamada qualificada `extensions.hmac`** — `20260625090000_schema.sql:16` (sem `with schema extensions`) vs `20260628220000:112` e `20260628360000:44` (funções com `set search_path to ''`, qualificação obrigatória). Num Postgres local (fluxo de testes do SETUP.md) a extensão vai para `public` e `obter_cache_pins` falha em runtime; nenhum teste a exercita. No Supabase cloud espera-se que exista em `extensions`: `[a verificar na BD]`.
12. **`picagem_recusada` sem GRANT de tabela explícito** — `20260628240000` só tem grant de EXECUTE na RPC. Na BD real funciona hoje **apenas** por default privileges legados (confirmado por consulta read-only: `has_table_privilege('authenticated', …, 'select') = true`, ACL `arwdDxtm` também para `anon`); `supabase/config.toml:19-24` avisa que o comportamento always-revoked se torna permanente em 2026-10-30 — tabelas futuras (ou branch/reset) deixarão de receber o grant implícito e o padrão de engolir erros (ponto 4) esconderia a falha.
13. **Admin consegue ler `kiosk.chave_hmac`** — grant de tabela inteira `20260628200000:42` + policy `admin_empresa` FOR ALL; segredo de dispositivo legível no painel.
14. **Policies `admin_empresa` de `autorizacao` e `kiosk` omitem `TO authenticated`** (`20260628180000:41-44`, `20260628200000:37-40`) — aplicam-se a PUBLIC; inócuo hoje (anon sem grants nas migrações, mas com grants na BD real via default privileges — ver ponto 12), menos estrito que o resto do esquema.
15. **`kiosk_insert` em picagem/checklist_resposta/acao_corretiva não força `loja_id`** — gap intra-empresa documentado no próprio ficheiro (`20260626100000:84-86`) e em docs/sprint1.md:33.
16. **`picagem_recusada.tipo` é text sem CHECK** e `reportar_picagem_recusada` insere `p_tipo` sem validar contra os 4 tipos (`20260628240000:24`).
17. **`limpar_autorizacoes` só revoga EXECUTE de PUBLIC** (`20260628260000:35`) — grants explícitos dos default privileges a authenticated/anon sobreviveriam; `purgar_fotos_expiradas` usa o padrão correto (`20260628340000:73`). ACLs efetivas: `[a verificar na BD]`.
18. **`/colaboradores/novo` assume que a RPC devolve linha** — [novo/page.tsx:53-54](apps/admin/app/(painel)/colaboradores/novo/page.tsx#L53-L54) rebenta com TypeError se `data` vier null.
19. **Listagem de picagens truncada a 300 linhas sem paginação nem aviso** ([registos/page.tsx:95](apps/admin/app/(painel)/registos/page.tsx#L95)).
20. **Job `purgar-fotos` depende de passo manual** — segredo `service_role_key` no Vault (`20260628340000:17-20`); sem ele o job falha todas as noites. Criado? `[a verificar na BD]`. URL do Storage cravado na função (`:40`).
21. **Drain sem backoff nem teto de tentativas** ([outbox.ts:267-271](apps/kiosk/lib/outbox.ts#L267-L271) + ciclo de 15 s); fotos base64 na SQLite sem limite de fila nem redimensionamento.

## 4. Parcial / em casca

- **Ficha do colaborador** — 1 de 5 tabs funcional ("PIN / Picagem": picagens do dia, horas, anular, adicionar); Informação (tab por omissão), Documentos, Horário e Férias são placeholder "em construção" ([colaboradores/[id]/page.tsx:284-295](apps/admin/app/(painel)/colaboradores/[id]/page.tsx#L284-L295)). A tab "PIN / Picagem" não tem nenhuma funcionalidade de PIN (sem "gerar novo").
- **Tab Checklists em /registos** — placeholder explícito "Frente B do roadmap" ([registos/page.tsx:392-397](apps/admin/app/(painel)/registos/page.tsx#L392-L397)).
- **Início** — 3 KPIs reais + 3 cartões "Em breve" (Quem está a trabalhar, Tarefas HACCP, Vera).
- **Exportação** — só xlsx; **CSV e PDF sem qualquer código** (grep vazio em apps/admin), apesar do doc 08:43 os listar.
- **Cálculo de horas** — só por dia (`vista_horas_dia`); agregação semana/mês deixada como "GROUP BY por cima" (`20260628300000:20`).
- **`/picagens`** — rota legada, só redirect.
- **Cobertura de testes SQL** — termina na vista de picagem (08); toda a fase 2+ (idempotência, bilhete, revogação, cache PIN, offline, recusas, sequência, imutabilidade, correções, bloco, folha, retenção) sem teste dedicado; não existe `07_*.sql` (salto de numeração); sem runner npm (correm-se via psql em modo Session).
- **Tabelas HACCP e `notificacao`** — existem desde o schema inicial com RLS, mas sem motor, UI ou consumo.

## 5. Não começado (do que os docs preveem)

- **Frente B — Checklists HACCP** (doc 08:49-56): construtor de templates, motor de conformidade, preenchimento no kiosk, notificações (email/Resend), agendamento/instâncias em falta, Vera + RAG.
- **Frente C — Camada RH** (doc 08:58-68): tabela cifrada de dados fiscais, bucket `documentos_colaborador`, aptidão médica/cert. manipulador, departamentos, horário, férias, custo-hora com role própria.
- **Dashboard real do Início** (doc 08:77) — depende de A+B.
- **Deteção de discrepância `momento_dispositivo` vs `momento_servidor`** (doc 08:44) — as colunas existem desde o schema inicial, mas não há nenhuma lógica ou UI de deteção.
- **Admin-loja** (adiado de propósito, docs/sprint1.md:31) e fecho do gap intra-empresa com `loja_id` denormalizado (sprint1.md:33).
- **Diferidos** (doc 08:137-144): Stripe enforcement, WhatsApp, app stores/build Android, verificação EUIPO, PowerSync, novos eventos autenticados.

## 6. Divergências docs ↔ código

1. **Doc 08 diz Frente A por fazer; o código mostra-a maioritariamente implementada.** docs/08-roadmap.md:30 ("registo legal… não"), :40 (cálculo de horas), :41 (validação de sequência), :42 (imutabilidade), :45 (job de expiração da foto) e :89 ("Tab Validações ⟵ Frente A") → tudo implementado (`20260628290000`–`20260628340000`, [validacoes.tsx](apps/admin/app/(painel)/registos/validacoes.tsx)); :43 (exportação) implementado parcialmente — xlsx sim, CSV/PDF não.
2. **Doc 08:74 diz "o Início é a mesma lista de Colaboradores; o nome liga a uma página que não existe"** → refutado: o Início é um dashboard de KPIs ([page.tsx:15-31](apps/admin/app/(painel)/page.tsx#L15-L31)) e a página do colaborador existe ([colaboradores/[id]/page.tsx](apps/admin/app/(painel)/colaboradores/[id]/page.tsx)); zero links mortos.
3. **Doc 08:25 diz "editar (`atualizar_colaborador`)" e "criar (… `gerar_novo_pin`)" feitos** → ambas as RPCs estão **órfãs** (zero chamadas em apps/; grep exaustivo). Nuance descoberta via git: a funcionalidade existiu (commit `3a91986`, Sprint 2) e foi **removida na reescrita da ficha como stub** (commit `032097d`) — regressão de UI não refletida no doc. As RPCs, migrações e testes SQL continuam válidos; a recomendação natural é reconectar a UI, não apagar.
4. **Doc 08:113 (decisão fechada) "PIN nunca é lido — o admin define/gera, nunca vê; a tab PIN mostra 'gerar novo'"** → violado: o ecrã de criação mostra o PIN em claro ([novo/page.tsx:64-67](apps/admin/app/(painel)/colaboradores/novo/page.tsx#L64-L67), com o texto "Comunica este PIN ao colaborador"); a tab "PIN / Picagem" não tem botão "gerar novo" nem chamada a `gerar_novo_pin`; e ambas as RPCs devolvem o PIN em claro (`20260626130000:76,:102`). Só a vertente BD (leitura direta da coluna) está respeitada.
5. **Doc 08:17/19 dá a captura como "completa e testada"** → a captura está completa, mas "testada" não se sustenta: os testes 06/08 chamam uma assinatura dropada e nada da fase 2+ tem teste (ver secção 4).
6. **README.md:2 descreve "SaaS multi-tenant de conformidade HACCP"** → HACCP não começado (o próprio doc 08:31 o diz); descrição aspiracional.
7. **SETUP.md é histórico do Sprint 0, não guia atual**: recomenda Frankfurt/Ireland (SETUP.md:16) quando o doc 08:13 afirma Paris (eu-west-3); usa o nome de projeto "haccp-saas" (SETUP.md:31), anterior à marca; só cobre as migrações 0900/0901 + seed (SETUP.md:46) e descreve a policy RLS uniforme que o Sprint 1 substituiu.
8. **Docs 00–07 referenciados mas inexistentes** — docs/08-roadmap.md:3,5 remete para `00`(contexto), `01`(BD), `02`(stack), `03-roadmap-sprints`, `04`(HACCP), `05`(AI/Vera), `06`(jurisdição RH), `07`(offline); nenhum existe no repo (só `08-roadmap.md` e `sprint1.md`).
9. **Doc 08:20 "foto não retida em recusas"** → cumprido na outbox (`foto_b64=''`), mas o ficheiro temporário da câmara fica no cache do SO (secção 3, ponto 9) — a garantia é parcial.

## 7. Dívida técnica e riscos (ordenado por gravidade)

1. **[Crítico] Semântica de anuladas inconsistente no coração do registo legal** — `sequencia_valida` (`20260628290000:30-40`) e `iniciar_picagem` (`20260628200000:177-187`) incluem anuladas; `obter_cache_pins` (`20260628360000:51`), `vista_horas_dia` (`20260628310000:164`) e o pré-flight do bloco (`20260629120000:133`) excluem. Consequências reais: recusas erradas no drain offline após uma anulação; dias "partidos" no cálculo de horas via fluxo online. A semântica pretendida (excluir) está declarada no próprio repo (`20260629120000:21-23`).
2. **[Alto] Erros engolidos no admin (9 locais, secção 3.4)** — em produção, uma falha de RLS/grant/rede mostra KPIs a 0 e faz desaparecer o painel de recusas sem qualquer sinal. Combinado com o risco 4, uma mudança de default privileges tornaria a app silenciosamente cega.
3. **[Alto] Decisão de segurança do PIN violada na UI + PIN em plaintext na BD** — exposição em claro na criação (secção 3.5); `trabalhador.pin` guardado em plaintext (decisão documentada em `20260626110000:12-13`, mas o PIN viaja em claro para o browser do admin via retorno das RPCs).
4. **[Alto] Grants dependentes de default privileges legados** — `picagem_recusada` sem GRANT explícito (funciona por ACL legada, que a Supabase torna always-revoked em 2026-10-30, `supabase/config.toml:19-24`); `anon` com privilégios de tabela na BD real; `limpar_autorizacoes` com revoke incompleto (`20260628260000:35`). Verificações pendentes na BD real: migrações aplicadas (31), extensões pg_cron/pg_net, `cron.job` + `job_run_details`, segredo `service_role_key` no Vault, grants efetivos, ACLs de funções — `[a verificar na BD]` (6 consultas read-only chegam).
5. **[Alto] Cobertura de testes** — testes 06/08 obsoletos (falham contra o schema atual); zero testes para as 20 migrações da fase 2+; nenhuma RPC SECURITY DEFINER tem teste; `obter_cache_pins`/`extensions.hmac` nunca exercitada (risco 8 nunca seria apanhado localmente); sem runner npm.
6. **[Médio] Kiosk — recusas online órfãs, estado offline incompleto, classificação por regex** (secção 3, pontos 6-8) e ficheiro temporário da câmara com rostos no cache do SO (ponto 9).
7. **[Médio] Lógica duplicada que devia viver em `packages/core`** (hoje o core só tem tipos): helpers de fuso Europe/Lisbon reimplementados byte-a-byte em 5 ficheiros ([colaboradores/[id]/page.tsx:32-46](apps/admin/app/(painel)/colaboradores/[id]/page.tsx#L32-L46), [validacoes.tsx:30-42](apps/admin/app/(painel)/registos/validacoes.tsx#L30-L42), [registos/page.tsx:40-54](apps/admin/app/(painel)/registos/page.tsx#L40-L54), [PicagemScreen.tsx:81-88](apps/kiosk/PicagemScreen.tsx#L81-L88), [outbox.ts:187-195](apps/kiosk/lib/outbox.ts#L187-L195)); union de tipos de picagem + labels PT declarados 4× com textos divergentes ("Início de pausa" vs "Início intervalo" vs "Início pausa"); máquina de transições em TS ([PicagemScreen.tsx:67-79](apps/kiosk/PicagemScreen.tsx#L67-L79)) e em SQL (`20260628290000:42-48`) sem fonte única; `paredeParaUTC` local em vez de partilhado; `diasEntre`/`diasAtras` copiados dentro do admin.
8. **[Médio] Dependências** — `xlsx` ^0.18.5 estagnado com CVEs conhecidas (prototype pollution CVE-2023-30533, ReDoS CVE-2024-22363; correções só no CDN da SheetJS) usado em [validacoes.tsx:3](apps/admin/app/(painel)/registos/validacoes.tsx#L3); `@corevero/core` importado sem estar declarado (dependência fantasma via hoisting, [apps/admin/lib/supabase.ts:2](apps/admin/lib/supabase.ts#L2)); `@supabase/ssr` declarada e nunca usada (apps/admin/package.json:12); `packageManager: yarn@1.22.22` na raiz com `package-lock.json` do npm (instalações não reprodutíveis); react 19.2.4 vs 19.2.3 e TS ^5 vs ~6.0.3 desalinhados entre apps; Next 16 e Expo SDK 56 são majors de ponta (risco assumido nos AGENTS.md).
9. **[Médio] pgcrypto/`extensions.hmac`** — falha garantida em Postgres local; no remoto `[a verificar na BD]` (secção 3.11).
10. **[Baixo] Restantes**: admin lê `kiosk.chave_hmac`; policies sem `TO authenticated` em autorizacao/kiosk; `picagem_recusada.tipo` sem CHECK; guarda de sessão só client-side; URL/chave Supabase hardcoded no kiosk ([supabase.ts:6-7](apps/kiosk/lib/supabase.ts#L6-L7)); limite 300 sem paginação; `verificacao_pertence_kiosk` obsoleta nunca dropada (`20260628120000:26-31`); `.env.local` e `.DS_Store` não versionados (correto). TODOs/FIXMEs/@ts-ignore no código próprio: **zero**. `console.*`: **zero**.

## 8. Recomendações imediatas (máx. 5, ordenadas)

1. **Fechar a divergência de anuladas**: acrescentar `and not p.anulada` a `sequencia_valida` (`20260628290000:30-40`) e a `iniciar_picagem` (`20260628200000:179-187`) numa nova migração — elimina as recusas offline erradas e os dias partidos; o próprio repo já marca isto como "item à parte".
2. **Executar as 6 verificações read-only na BD real** (projeto `xghfsudvpsgqkslobttj`): migrações aplicadas vs 31 locais; extensões pg_cron/pg_net e schema do pgcrypto; `cron.job` + `cron.job_run_details` (o `purgar-fotos` pode estar a falhar todas as noites); segredo `service_role_key` no Vault (só existência, nunca o valor); grants efetivos de `picagem_recusada`; ACLs das funções — e acrescentar GRANTs/REVOKEs explícitos em migração antes de 2026-10-30.
3. **Parar de engolir erros no admin**: tratar `error` nos 9 locais da secção 3.4 (no mínimo, um estado de erro visível nos KPIs e no painel de recusas) e incluir `details`/`hint` do PostgREST onde já se mostra `error.message`.
4. **Criar o módulo partilhado em `packages/core`** (paredeParaUTC, diaLisboa/horaLisboa/hojeLisboa/diasEntre, union `TipoPicagem` + labels, `opcoesPara`) e usar `paredeParaUTC` no modal Nova Picagem ([registos/page.tsx:485](apps/admin/app/(painel)/registos/page.tsx#L485)); tipar o cliente do kiosk com `Database`.
5. **Repor a edição de colaborador e a gestão de PIN sem expor o PIN** (reconectar `atualizar_colaborador`/`gerar_novo_pin` à ficha, com "gerar novo" que comunica o PIN sem o persistir no ecrã de listagem), atualizar `docs/08-roadmap.md` e `SETUP.md` ao estado real, e refazer `tests/06`/`tests/08` para a assinatura atual de `registar_picagem`.
