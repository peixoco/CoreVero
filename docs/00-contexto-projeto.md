# 00 — Contexto do Projeto (memória para novos chats)

> Documento de continuidade. Lê isto primeiro: resume o produto, as decisões fechadas, o estado atual e os fios em aberto, para retomar o trabalho sem re-explicar tudo.
> Documentos de apoio já no projeto: `01-arquitetura-bd.md`, `02-stack-e-padroes.md`, `03-roadmap-sprints.md`, `04-levantamento-haccp.md`.

---

## 1. O que é o produto

SaaS **multi-tenant** de **conformidade HACCP com atribuição autenticada**, para restaurantes em Portugal. Combina:

- **Controlo de assiduidade (picagem)** — colaborador identifica-se num kiosk partilhado por código pessoal + foto.
- **Monitorização HACCP** — checklists tipadas com limites críticos e ações corretivas.

A picagem e a conclusão de checklist partilham o mesmo primitivo de prova: **quem + onde + quando + foto**.

Identidade a vender: não é "app de picagem com checklists ao lado" — é um **sistema de conformidade HACCP com prova autenticada**.

---

## 2. Decisões de produto fechadas

- **Multi-tenant desde o início.** A `empresa` é a fronteira de isolamento. Mantém-se mesmo na fase de teste com um só restaurante — construir single-tenant e converter depois é o erro que se evita de propósito.
- **Preço por lugares (seats):** nº de colaboradores licenciados + nº de lojas licenciadas. Ativos não podem exceder o limite pago. Desativar preserva histórico e liberta lugar.
- **Colaborador pertence à empresa e pica em qualquer loja dela.** `trabalhador_loja` é afetação/escala, não governa permissão de picagem.
- **Checklists configuráveis pelo admin, NUNCA em código.** São linhas (`checklist_template` + `checklist_item`). Um template vive na empresa (`loja_id` nulo) ou é próprio de uma loja (`loja_id` preenchido). Motor de conformidade genérico. É isto que torna o produto escalável.
- **Fase atual:** teste no restaurante próprio (um tenant), sem faturação, notificações por email.

---

## 3. Arquitetura de dados (resumo — ver `01`)

- `empresa_id` em **todas** as tabelas (desnormalização deliberada) + **RLS** uniforme `empresa_id = empresa_atual()`. Claim no JWT (`app_metadata`).
- **`verificacao`** = primitivo partilhado (trabalhador + loja + `momento_dispositivo` + foto). `picagem` e `checklist_instancia` referenciam-no. Reutilizável para futuros eventos (ex. receção de mercadoria).
- Checklists: `checklist_template` (com `versao`, `frequencia`) → `checklist_item` (`tipo_resposta`, `unidade`, `limite_min/max`) → `checklist_instancia` (congela `template_versao`, `due_at`, `estado`) → `checklist_resposta` (`valor`, `conforme`) → `acao_corretiva` (obrigatória se `conforme=false`, autenticada).
- `notificacao` multi-canal (`canal`: email/in_app/whatsapp).
- **Dois tipos de utilizador:** admins/gestores = contas Supabase Auth; colaboradores = sem login, código + foto num kiosk que se autentica como a loja.

---

## 4. Stack (ver `02`)

- Kiosk: **Expo (React Native)**. Admin: **web (Next.js/Vite)**. TypeScript partilhado.
- **Supabase** (Postgres + Storage + Auth + Edge Functions), região **UE** (Frankfurt/Irlanda).
- Notificações: **Resend (email)** no MVP; WhatsApp Business API pós-MVP.
- Faturação: **Stripe**, adiado (fase de teste).
- Disparo de notificações/jobs: **Edge Functions** (server-side).

---

## 5. Padrões de design (ver `02`)

- **Captura imune à rede (outbox):** um só caminho de escrita — fila local que drena quando há rede. Online é a regra, offline a exceção. Cache de leitura fina (templates, limites, códigos). Hora do dispositivo autoritária + hora de servidor para auditoria. Sem PowerSync por agora.
- **Ação corretiva forçada localmente** no momento da captura quando fora do limite — não depende da notificação chegar.
- **Versionamento de template** congelado na instância (prova HACCP interpretável mesmo após mudança).

---

## 6. RGPD e fronteiras legais

- **A foto é atribuição por revisão humana, NÃO biometria.** Pela RGPD (Considerando 51), uma foto só é dado biométrico se for processada por reconhecimento facial automático. **Nunca adicionar matching facial automático** — isso tornaria o tratamento biométrico (art. 9.º) e dispara um regime pesado.
- **Retenção:** separar a prova de conformidade (HACCP, retenção longa) da foto de atribuição (RGPD, retenção curta, purgável por job).
- **A confirmar com jurista RGPD:** base legal (art. 6.º), prazos de retenção, informação aos trabalhadores.

---

## 7. AI para autoria de checklists — decisões

**Papel da AI:** onboarding — **entrevista** o restaurante (tipo de cozinha, nº de colaboradores, equipamentos de frio, fritadeira, banho-maria, receção, pragas/água/calibração) e **recomenda quais templates do catálogo ativar e parametrizar**. NÃO inventa checklists.

**Regra dura (conformidade):** a AI rascunha, **o humano aprova**. A AI **nunca** é autoridade final sobre um limite crítico. Gate de aprovação humana antes de qualquer template ir para produção.

**Origem dos limites críticos — RAG (decidido):** os limites vêm do **regulamento que o utilizador indexa** (markdown), via **Retrieval-Augmented Generation**. A AI vai buscar o trecho exato e responde só com base nele; se o limite não estiver no texto, diz que não sabe — **nunca inventa números**. Motivo: em testes, modelos pequenos inventaram limites errados com confiança (ex.: cozedura ≥70 °C em vez de ≥75 °C; congelados ≤−12 °C em vez de ≤−18 °C). Confiar na memória do modelo é inseguro num contexto HACCP.

**T&C:** incluir disclaimer "não substitui validação por consultor de segurança alimentar". Nota: o disclaimer protege juridicamente, **não** protege o cliente de um limite errado — por isso o RAG + a regra "nunca inventes números" não são opcionais.

**Onde NÃO ir:**

- Não usar a **API da Anthropic** neste projeto (decisão do utilizador).
- Não usar o **tier grátis do Gemini** em produção: os termos da Google exigem serviço pago para clientes na UE e treinam nos dados do tier grátis.

**Stack de AI (self-hosted, RGPD-limpo):**

- Motor: **Ollama** (MVP) → **vLLM** (escala/concorrência). Ambos com API compatível-OpenAI e structured outputs.
- Modelo: **Mistral Small 4** (EU, Apache 2.0, multimodal — cobre import de documentos) como aposta; alternativas de texto leves: **Qwen 8B**, **Llama 8B**, **Phi-4-mini**.
- **Camada de abstração de provider** (o contrato é o JSON Schema; o modelo/endpoint é configuração). Trocar é config, não reescrita.
- **Structured outputs** com JSON Schema mapeado para `checklist_template`/`checklist_item`.

**Hosting da inferência (sem custo inicial):**

- **Oracle Cloud Always Free A1** (CPU ARM, 4 OCPU / 24GB RAM, região UE, permanente) — corre modelos pequenos de texto. Bom para o onboarding (que é só texto). Não aguenta bem o Mistral Small 4 nem visão (precisa GPU).
- **Serverless GPU escala-a-zero** (RunPod/Modal) — paga-se por uso, $0 quando inativo; para visão (import de documentos) ou escala.
- Local só para experimentar, não como endpoint de produção.

**Estado do teste de qualidade (Opção A — chat web, sem hospedar):** concluído com sucesso. Mistral e Qwen pequenos fizeram o onboarding bem (desativaram óleo sem fritadeira, escalaram temperaturas de frio, fizeram perguntas de confirmação). Confirmou que um modelo pequeno chega para a tarefa. O senão observado — invenção de limites — é o que o RAG resolve.

---

## 8. HACCP — conteúdo (ver `04`)

Catálogo de 7 templates de arranque: (1) temperaturas de frio, (2) confeção e serviço, (3) óleo de fritura [só com fritadeira], (4) receção de mercadorias, (5) higienização, (6) higiene pessoal/abertura, (7) pré-requisitos periódicos.

Distinção: **PCC** (numéricos, com ação corretiva — temperaturas, óleo) vs **PRP** (booleanos — higiene, limpeza, pragas).

Valores indicativos PT (a validar por responsável de segurança alimentar): cozedura/reaquecimento ≥75 °C; conservação a quente ≥65 °C; refrigeração 0–5 °C; congelação ≤−18 °C; óleo ≤180 °C e ≤25 % compostos polares (Portaria 1135/95).

---

## 9. Nota sobre o "SARA"

SARA é o **software de criação de checklists / sistema HACCP existente** da empresa — **não é uma pessoa nem uma autoridade**. O plano é importar para a nova plataforma o conteúdo que já existe no SARA. Atenção: a frase "validar com SARA" (usada por engano em prompts anteriores) está **errada** — a validação de limites críticos é feita por um **responsável de segurança alimentar humano**, não por software.

---

## 10. Fios em aberto / próximos passos

- **Detalhar o RAG** para os limites HACCP a partir do regulamento indexado (chunking, instrução "cita o trecho / nunca inventes", como o trecho entra no prompt).
- **Fechar o hosting da AI** (Oracle A1 vs serverless) — quase decidido.
- **Doc 05 — autoria assistida por AI** (proposto, ainda por escrever): camada de abstração + RAG + JSON Schema + hosting faseado.
- **Iniciar Sprint 0** (fundações: Supabase UE, esquema, RLS).
- **Em paralelo (prazo de calendário):** parecer jurídico RGPD; limites HACCP definitivos por responsável de segurança alimentar.

---

## 11. Prioridades do projeto (por ordem)

1. Rapidez a lançar (MVP) · 2. Custo baixo de manutenção · 3. Experiência mobile · 4. Presença nas app stores.
