# 03 — Roadmap e Sprints

> Plano faseado até MVP e além. Cada sprint tem objetivo, entregáveis e critério de pronto (DoD).
> Pressuposto: equipa pequena, sprints de ~2 semanas. Ajustar à capacidade real.
> Fase atual: **teste no restaurante próprio** (um tenant). Multi-tenant na mesma, sem faturação, notificações por email.

---

## Trabalho em paralelo (arranca já, fora do código)

Estas dependências têm prazo de calendário e não aceleram por escrever código. **Iniciar no dia 1.**

- [ ] Plano HACCP de referência: extrair do **SARA** os itens, limites críticos e frequências para os primeiros templates.
- [ ] Parecer jurídico RGPD: base legal (art. 6.º), prazos de retenção, info aos trabalhadores.
- [ ] Decisão de região UE (Frankfurt vs Irlanda).
  > **Adiado** (não bloqueia o MVP de teste): WhatsApp Business API (Meta) e Stripe. Para MVP, notificações por **email (Resend)** e **sem faturação**.

---

## Sprint 0 — Fundações

**Objetivo:** projeto de pé, esquema e isolamento corretos antes de qualquer feature.

> Mesmo testando só no restaurante próprio (um tenant), o esquema multi-tenant e a RLS ficam desde já. Construir single-tenant e converter depois é o erro caro que este projeto evita de propósito.

Entregáveis:

- Projeto Supabase criado em região UE; DPA aceite.
- Repositórios: kiosk (Expo) e admin (web), TypeScript partilhado.
- Esquema completo das tabelas (doc 01) aplicado via migrações.
- **RLS ativa em todas as tabelas** + `empresa_atual()` + policy-tipo.
- Seed de uma empresa de teste (o restaurante) com a(s) sua(s) loja(s) e colaboradores.
  **DoD:** um utilizador da Empresa A, por query, não consegue ler nenhuma linha da Empresa B. Testado (mesmo com só um tenant real, a policy é verificável com um tenant-seed extra).

---

## Sprint 1 — Identidade e acesso

**Objetivo:** admins entram e veem só o seu; kiosk autentica-se como loja.

Entregáveis:

- Auth de admins; claim `empresa_id` em `app_metadata` no convite/signup.
- Âmbitos `empresa` e `loja` com policies diferenciadas.
- Identidade de kiosk por loja (token/conta dedicada) com permissão só de inserção na sua loja.
- Gestão de lojas e colaboradores no admin (CRUD). Estrutura de **enforcement de lugares** pronta; limites definidos manualmente nesta fase (sem Stripe).
  **DoD:** admin de loja não vê outras lojas; o kiosk só consegue inserir eventos da sua loja.

---

## Sprint 2 — Picagem (caminho feliz, online)

**Objetivo:** o núcleo do produto a funcionar com rede.

Entregáveis:

- Ecrã de kiosk: selecionar/inserir código → captura de foto → cria `verificacao` + `picagem`.
- Upload da foto para bucket UE.
- `momento_dispositivo` autoritário; `momento_servidor` registado.
- Listagem de picagens no admin, por loja e período.
  **DoD:** uma picagem de entrada e saída aparece corretamente no admin com foto e horas.

---

## Sprint 3 — Captura imune à rede (outbox)

**Objetivo:** a captura deixa de depender da rede.

Entregáveis:

- Outbox local (fila) como único caminho de escrita; drena ao reconectar.
- Cache de leitura fina (códigos ativos, templates, limites) no kiosk.
- Fotos na fila com limpeza após confirmação de upload.
- Indicador de pendentes na UI.
  **DoD:** com rede desligada, três picagens são capturadas com a hora certa e sobem intactas ao reconectar.

---

## Sprint 4 — Checklists HACCP (construtor + preenchimento)

**Objetivo:** monitorização tipada com limites e conformidade, **toda definida pelo admin, nunca em código**.

Entregáveis:

- **Construtor de templates no admin (feature central):** criar `checklist_template` (empresa ou própria de loja), adicionar itens tipados com `tipo_resposta`, `unidade`, `limite_min/max`, definir `frequencia` e `versao`. Conteúdo inicial importado do plano HACCP do SARA.
- Atribuição de templates a lojas (`checklist_template_loja`).
- Kiosk: preencher checklist autenticada (cria `verificacao` + `instancia` + `respostas`); `template_versao` congelada.
- Motor genérico de conformidade: calcula `conforme` a partir dos limites do item; **ação corretiva forçada localmente** quando fora do limite — sem código por checklist.
  **DoD:** o admin cria uma checklist nova (ex. temperaturas) sem alterações de código, e registar um valor fora do limite obriga a ação corretiva antes de fechar.

---

## Sprint 5 — Notificações (email)

**Objetivo:** desvios alertam os responsáveis.

Entregáveis:

- Entidade `notificacao` multi-canal (canal `email` para MVP).
- Edge Function: ao entrar `resposta` não conforme, cria notificação e envia email via **Resend**.
- Configuração de destinatários por loja.
- Estado de envio registado (enviada/falhou). WhatsApp fica como canal a acrescentar pós-MVP sem refazer a entidade.
  **DoD:** um valor fora do limite gera um email ao destinatário configurado; estado registado.

---

## Sprint 6 — Agendamento e instâncias em falta

**Objetivo:** mostrar não só o feito, mas o que faltou (o que a inspeção quer).

Entregáveis:

- `frequencia` no template gera instâncias `pendente` com `due_at`.
- Marcação automática de `em_falta` quando ultrapassa o prazo.
- Vista de conformidade no admin: feitas vs em falta, por loja e período.
  **DoD:** uma checklist diária não feita aparece como `em_falta` no relatório do dia.

---

## Sprint 7 — Retenção e robustez

**Objetivo:** cumprir RGPD/HACCP e endurecer (parte disto pode subir de prioridade se o teste lidar com dados reais de trabalhadores).

Entregáveis:

- Job de expiração de fotos (retenção curta) sem tocar nos registos de conformidade.
- Append-only/auditoria nas respostas e ações corretivas.
- Deteção de discrepância `momento_dispositivo` vs `momento_servidor`.
- Exportação de registos HACCP para inspeção.
  **DoD:** fotos expiram no prazo definido; a prova de conformidade mantém-se e é exportável.

---

## Pós-teste (quando houver clientes externos)

- **Faturação (Stripe):** subscrição por lugares + lojas; ativar o enforcement (estrutura já existe do Sprint 1); gestão de plano no admin.
- **WhatsApp:** acrescentar canal à entidade `notificacao` (verificação Meta + templates aprovados).
- App stores (Expo build/submit) se necessário para confiança comercial.
- Relatórios e dashboards avançados; multi-idioma.
- Reavaliar PowerSync se a sincronização offline crescer.
- Novos tipos de evento autenticado reutilizando `verificacao` (ex. receção de mercadoria).
