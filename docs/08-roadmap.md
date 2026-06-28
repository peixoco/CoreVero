# 08 — Roadmap Atualizado (estado real e próximas frentes)

> Documento de continuidade e plano. Captura o estado **real** do produto e sequencia o que falta. Substitui, na parte de *sequência*, o que o `03-roadmap-sprints.md` tem de desatualizado (o 03 mantém-se válido para a estrutura interna dos sprints HACCP).
> Lê isto para saber o que está feito, o que falta, e por que ordem — sem reabrir decisões já fechadas.
> Relacionados: `00` (contexto), `01` (BD), `02` (stack), `03` (sprints HACCP), `04` (HACCP conteúdo), `05` (AI/Vera), `06` (jurisdição RH), `07` (offline).

---

## 1. Estado real — o que ESTÁ feito

### Núcleo e infraestrutura
- Multi-tenant com `empresa_id` em todas as tabelas + RLS uniforme; claim no JWT (`app_metadata`).
- Supabase UE (Paris, eu-west-3). Storage privado (`picagens`) com RLS.
- Dois tipos de utilizador: admins (Auth) e kiosk (conta por loja). Helpers `empresa_atual`/`loja_atual`/`is_admin`/`is_kiosk`/`kiosk_ativo`.
- Marca CoreVero (Tinta/Teal/Papel/Cinza, Space Grotesk, visto + wordmark).

### Picagem (assiduidade) — CAPTURA completa e testada
- **Online:** `iniciar_picagem` valida PIN server-side e emite bilhete; `registar_picagem` consome-o. PIN nunca lido pelo kiosk.
- **Offline (3a + 3b):** outbox local (SQLite), cache de PIN (HMAC + chave por dispositivo no Keychain), validação offline, re-validação no drain (apanha cache obsoleta), idempotência, hora autoritária do toque.
- **Segurança do kiosk:** revogar/reativar (acesso) + terminar sessão (autenticação) como eixos separados; cache TTL (7 dias) protege tablet roubado offline; foto não retida em recusas; limpeza de bilhetes via `pg_cron`.
- **Recusas expostas ao admin** (`picagem_recusada` + painel).
- **4 tipos de picagem**, incluindo `inicio_intervalo`/`fim_intervalo` — as **pausas já são capturadas** (doc 06 §8.1 parcialmente cumprido).

### Admin (web)
- Colaboradores: lista, criar (`criar_colaborador`/`gerar_novo_pin`), editar (`atualizar_colaborador`).
- Picagens: lista (`vista_picagem`) + painel de recusas.
- Definições: tabs Conta · Lojas · Dispositivos (revogar/reativar/terminar sessão).

### O que isto NÃO é ainda
- A **captura** está feita; o **registo legal de tempos** (horas, imutabilidade, exportação) **não**.
- **HACCP:** não começado.
- **Perfil rico do colaborador / camada RH:** não começado (mapeado no doc 06, não implementado).

---

## 2. As três frentes de trabalho

### Frente A — Picagens viram REGISTO LEGAL
O que falta para os eventos virarem prova aceitável pela ACT (Art. 202.º):
1. **Cálculo de horas** por dia/semana a partir de entrada/saída/pausas. *[núcleo da frente]*
2. **Validação de sequência** dos tipos (não permitir duas entradas seguidas) — pré-requisito para o cálculo ser fiável.
3. **Imutabilidade (append-only)** dos registos de tempo (triggers a impedir UPDATE/DELETE silencioso; correções por novo registo).
4. **Exportação** xlsx/CSV/PDF por dia/semana/mês (a tab "Validações"; inclui importar para corrigir).
5. **Deteção de discrepância** `momento_dispositivo` vs `momento_servidor`.
6. **Job de expiração da foto** (retenção curta RGPD), sem tocar na prova.

**DoD da frente:** o admin exporta as horas de um colaborador num mês, com pausas descontadas, num registo que não foi editado silenciosamente.

### Frente B — Checklists HACCP (Sprint 4+ do doc 03)
O segundo módulo central. Nada começado.
- **Construtor de templates no admin** (feature central): `checklist_template` + `checklist_item` tipados (tipo/unidade/limites/frequência/versão). Configuração como dados, nunca em código.
- **Motor de conformidade genérico:** calcula `conforme` dos limites; força ação corretiva quando fora.
- **Preenchimento no kiosk** (reutiliza `verificacao`); `template_versao` congelada.
- **Notificações** (email/Resend) ao desviar.
- **Agendamento + instâncias em falta** (mostrar o que faltou, não só o feito).
- **Vera + RAG** (docs 04/05) entram **aqui**, depois do motor base — tabela de limites como autoridade dos números, pgvector para citação. A AI rascunha, o humano aprova.

### Frente C — Camada RH (desbloqueia a página do colaborador)
Mapeada no doc 06, por implementar:
- **Tabela cifrada de dados fiscais** (NIF/NISS/IBAN): RLS + role de pagamentos + cifragem em repouso; **nunca no kiosk**.
- **Bucket `documentos_colaborador`** (contrato + adendas + recibos + justificações): admin-only, cifrado, retenção própria.
- **Aptidão médica + cert. manipulador:** status + datas, com alertas de expiração (sem conteúdo clínico).
- **Departamentos** configuráveis por tenant (config como dados).
- **Horário** (calendário com feriados; início/fim escalados por dia).
- **Férias** (saldo, marcados/gozados/por marcar).
- **Custo-hora / hora-extra:** dado sensível de folha — role de acesso próprio.

**DoD da frente (parcial):** a página do colaborador com as 5 tabs assenta em dados reais, com os fiscais e documentos na camada cifrada certa.

---

## 3. Navegação / Arquitetura de Informação (atravessa as três frentes)

Estado atual: o Início é a **mesma** lista de Colaboradores (duplicado); o nome do colaborador liga a uma página que **não existe**.

Alvo:
- **Início → dashboard** (quem está a trabalhar/ausente por horário; tarefas HACCP pendentes/concluídas; acesso à Vera em destaque). *Depende de A (horas) + B (checklists).*
- **Registos** (ex-"Picagens") com submenu: **Picagens** · **Checklists** (B) · **Validações** (A, export/import xlsx).
- **Colaboradores → lista → página do colaborador** com 5 tabs (Informação · PIN/Picagem · Documentos · Horário · Férias). *Depende de C.*

Regra: a **casca** de navegação (renomear, submenu, desduplicar o Início) é barata e pode vir já; o **conteúdo** de cada página depende da frente respetiva.

---

## 4. Grafo de dependências (porque a ordem não é livre)

- **Dashboard do Início** ⟵ Frente A (horas) + Frente B (tarefas). Construir antes = gráficos sem dados.
- **Página do colaborador** ⟵ Frente C (tabela fiscal cifrada, documentos, horário, férias).
- **Tab Validações** ⟵ Frente A (export).
- **Tab Checklists** ⟵ Frente B.
- **Cálculo de horas** ⟵ validação de sequência dos tipos.
- **Export ACT** ⟵ horas + imutabilidade.
- **Casca de navegação** ⟵ nada (pode arrancar já).

---

## 5. Sequência recomendada

0. **Casca de navegação** (barato; desbloqueia a IA e para de confundir): desduplicar o Início, renomear para Registos com submenu (páginas internas como casca).
1. **Escolher A ou B conforme a pressão do piloto:**
   - Se já há trabalhadores a picar a sério → **Frente A** (registo legal, ACT).
   - Se a ASAE/HACCP aperta primeiro → **Frente B** (checklists).
2. A outra das duas.
3. **Frente C** (camada RH) — desbloqueia a página do colaborador e o dashboard fica completo.
4. **Dashboard do Início** (já com dados de A e B).
5. **Retenção:** os 4 relógios independentes (doc 06 §5) e o job de expiração de fotos.

---

## 6. Decisões fechadas a respeitar (NÃO reabrir)

- **NIF/NISS/IBAN** → tabela cifrada separada, role de pagamentos, nunca no kiosk. Não são campos do perfil. *[doc 06]*
- **PIN nunca é lido** — o admin define/gera, nunca vê. A tab "PIN" mostra "gerar novo", não o PIN. *[Certain]*
- **Kiosk confinado** a picagem + checklist; tudo o resto é admin. *[doc 06 §3]*
- **Foto = atribuição por revisão humana, não biometria.** Nunca matching facial automático. *[doc 00 §6]*
- **Captura imune à rede** = feita (escrita + autorização offline). *[doc 07]*
- **Restaurante = responsável; SaaS = subcontratante** (DPA por cliente). *[doc 06 §2]*
- **Configuração como dados** (checklists, departamentos) — nunca em código.

---

## 7. Questões em aberto (fechar ANTES de construir o que delas depende)

**Legais (jurista RGPD + laboral — workstream paralelo, doc 06 §9):**
- Fórmula de **férias** (a base portuguesa anda nos ~22 dias úteis/ano com possível majoração; "2 dias/mês" é regra do 1.º ano com teto). **Configurável, não cravada.** *[Guessing no número; certo na regra de a não cravar]*
- **Prazos de retenção** exatos (foto, prova HACCP, contrato 5 vs 10 anos).
- **Fonte de feriados** (nacionais + municipais + móveis, por ano).
- **Formato** dos mapas de horário e de férias exigidos.

**Produto:**
- Qual frente (A ou B) primeiro, conforme o piloto.
- **Custo-hora/hora-extra:** que role vê custos.
- Segunda conta de kiosk para testar Android (chave por dispositivo — ver nota no histórico).

---

## 8. Diferido (não é agora, não bloqueia)

- **Faturação (Stripe)** — estrutura de lugares já existe; ligar o enforcement quando houver clientes externos.
- **WhatsApp** (canal extra na `notificacao`).
- **App stores** (Expo build/submit) — incl. build Android para teste.
- **EUIPO** — verificação formal da marca "CoreVero" (classes 9 e 42) antes de materiais definitivos.
- **PowerSync** — só se a sincronização offline crescer.
- **Novos eventos autenticados** reutilizando `verificacao` (ex. receção de mercadoria).

---

## 9. Princípios que guiam tudo (recap)

1. Rapidez a lançar (MVP) · 2. Custo baixo de manutenção · 3. Experiência mobile · 4. Presença nas app stores.
- Multi-tenant desde o início; RLS é a fundação de segurança.
- Um número legal (HACCP **ou** laboral) nunca vem de um palpite — vem da fonte citada ou de validação humana.
- Append-only e prova autenticada são o coração do produto: o que distingue isto de "uma app de picagem com checklists ao lado".
