# 10 — Visão: o potencial total da plataforma

> O que o CoreVero pode vir a ser: o **sistema operativo do restaurante** — gestão do negócio centralizada, na palma da mão do proprietário.
> Este documento é visão, não compromisso. Nada daqui entra antes de R1+R2 do roadmap (`09-pendentes-e-roadmap-lancamento.md`). Serve para: (a) desenhar hoje sem fechar portas de amanhã; (b) material de pitch; (c) ordenar a expansão por valor e dependência.
> Relacionados: `06-jurisdicao-rh.md` (fronteiras legais), `08-roadmap.md` (frentes), `05-autoria-ai.md` (padrão de AI grounded).

---

## 1. Tese

Um restaurante gere hoje o negócio em 6–10 ferramentas desligadas: POS, Excel de escalas, WhatsApp para comunicar com a equipa, papel para HACCP, email da contabilista, pasta física de contratos. O CoreVero já tem o que nenhuma dessas ferramentas tem: **o primitivo de prova autenticada** (quem + onde + quando + foto) e a fronteira multi-tenant limpa. Tudo o que se acrescenta herda essas duas propriedades.

A progressão natural:

**Fase atual** — conformidade (picagem legal + HACCP) → *"não levo multa"*
**Fase 2** — operação (comunicação, escalas, documentos) → *"a equipa funciona aqui dentro"*
**Fase 3** — inteligência (custos, margens, agentes) → *"vejo e controlo o negócio na palma da mão"*

Cada fase aumenta o preço defensável e o custo de sair (switching cost). *[Likely]*

---

## 2. O pré-requisito estrutural: a terceira camada de acesso

**Verdade primeiro:** quase tudo o que este documento descreve para o *colaborador* (notificações de horário, recibos, assinatura de contrato, chat) é impossível na arquitetura atual, porque **os colaboradores não têm login** — identificam-se por PIN+foto num kiosk partilhado, e o kiosk está deliberadamente confinado a picagem+checklist (doc 06 §3, decisão fechada e correta).

A solução **não** é alargar o kiosk. É criar a terceira camada:

| Camada | Quem | Autenticação | Vê |
|---|---|---|---|
| Kiosk | dispositivo partilhado | conta de loja | só picagem + checklists (inalterado) |
| Admin | dono/gestores | Supabase Auth | tudo |
| **Portal do colaborador** *(novo)* | cada trabalhador, no telemóvel pessoal | **Supabase Auth individual** (email/telefone + magic link ou password) | **só o seu**: horário, recibos, documentos, chat, férias |

Consequências:
- RLS nova: `trabalhador_id = auth do próprio` — o padrão RLS existente estende-se, não se refaz. *[Certain]*
- `trabalhador` ganha ligação opcional a `auth.users` (opcional porque nem todos aderem — o portal é benefício, não obrigação; a picagem continua no kiosk sem depender disto). *[Certain]*
- Distribuição: **PWA primeiro** (link enviado por SMS/email, zero fricção de app store), app nativa depois se justificar. *[Likely]*
- É o desbloqueador de §4, §5 e §6 abaixo. Sem esta camada, "recibos na app" e "assinatura de contrato" não têm onde acontecer.

---

## 3. Módulo: Comunicação (a morte do grupo de WhatsApp)

O grupo de WhatsApp do restaurante é o concorrente real: gratuito, universal e péssimo — mistura escala com memes, não tem prova de leitura e vive fora do controlo da empresa (RGPD: números pessoais, dados laborais em servidor da Meta).

| Feature | Descrição | Nota |
|---|---|---|
| Mural / anúncios | Gestor publica ("sábado fechados para evento privado"); colaboradores confirmam leitura | A **confirmação de leitura autenticada** é prova — coerente com o ADN do produto |
| Notificações de horário | Escala publicada/alterada → push/SMS ao afetado; alteração <24h assinalada | O horário vem da Frente C (R3) |
| Chat 1:1 e por área | Gestor↔colaborador; canal "cozinha", "sala" (áreas já existem no schema) | Realtime do Supabase cobre isto sem infra nova *[Likely]* |
| Pedidos estruturados | Troca de turno, marcação de férias, justificação de falta — como **fluxos com estado** (pedido→aprovação→registo), não conversa solta | É aqui que o chat deixa de ser chat e vira gestão |

**Regra de desenho:** os pedidos estruturados escrevem nas tabelas de RH (férias, escala) — o chat é interface, nunca a fonte de verdade. *[Certain]*

---

## 4. Módulo: RH completo (fecho do ciclo do colaborador)

### 4.1 Recibos de vencimento — reversão consciente de uma decisão fechada

O doc 06 §7 excluiu os recibos ("ficam com a contabilista"). Incluí-los **é possível e tem valor real** (o colaborador tem os recibos todos num sítio; o dono deixa de os reenviar por WhatsApp), mas é uma reversão que traz obrigações:

- O recibo entra como **documento selado** (PDF da contabilista, upload pelo admin ou por email-in), no bucket cifrado `documentos_colaborador` — nunca como campos processáveis. *[Certain]*
- **Retenção fiscal: 10 anos** (relógio próprio, doc 06 §5). *[Certain]*
- Acesso: admin com role próprio + **o próprio colaborador via portal** (§2). Nunca kiosk, nunca gestores só-HACCP. *[Certain]*
- Fluxo: admin carrega recibo no perfil → notificação push/email ao colaborador → colaborador vê/descarrega no portal → (opcional) confirmação de receção autenticada, que substitui o "assinar o duplicado" em papel. *[Likely]*
- Atualizar o doc 06 quando esta decisão for confirmada — o catálogo de dados §4 e as exclusões §7 ficam desatualizados.

### 4.2 Assinatura de contrato de trabalho — integrar, não construir

**Verdade primeiro:** um "sistema parecido ao DocuSign" feito em casa (desenhar assinatura no ecrã) produz uma **assinatura eletrónica simples** (SES) sob o eIDAS — admissível em tribunal mas de valor probatório fraco, precisamente no documento onde o valor probatório mais importa. O DocuSign não vale pelo desenho no ecrã; vale pela cadeia de prova certificada por baixo. *[Certain]*

Os três níveis eIDAS e o que implicam:

| Nível | O que é | Serve para contrato de trabalho? |
|---|---|---|
| SES (simples) | desenho no ecrã, checkbox | Fraco; contestável |
| AES (avançada) | ligada univocamente ao signatário, com deteção de alteração | Sim, na prática de mercado *[Likely]* |
| QES (qualificada) | certificado qualificado (em PT: **CMD — Chave Móvel Digital** / Cartão de Cidadão) | Equivalência plena à manuscrita *[Certain]* |

**Recomendação:** integrar um prestador que oficialize AES/QES — opções com API e presença ibérica: **Signaturit**, **Lleida.net**, DocuSign; ou a via nacional **CMD/AMA** (gratuita para o cidadão, exige integração com a AMA). O produto orquestra o fluxo (gerar contrato a partir da ficha → enviar para assinatura → guardar o assinado no bucket cifrado → marcar contrato ativo), o prestador dá a validade jurídica. Custo por assinatura (~0,5–2 €) é irrisório face ao risco de um contrato contestado. *[Likely nos preços; Certain na recomendação de não construir]*

O mesmo fluxo estende-se a: adendas, acordos de confidencialidade, entrega de EPI/fardamento, políticas internas com aceitação registada.

### 4.3 O resto do ciclo
- **Onboarding digital:** novo colaborador recebe link → preenche os próprios dados (com validação) → assina contrato (§4.2) → recebe PIN → aparece no kiosk. De horas de papel para minutos.
- **Alertas de expiração** (já previstos): aptidão médica, certificado de manipulador, fim de contrato a termo.
- **Mapa de férias e de horário** exportáveis nos formatos exigidos (a fechar com jurista — doc 08 §7).

---

## 5. Módulo: Controlo de custos (o coração da Fase 3)

### 5.1 Labour cost — a vantagem que já está construída

O CoreVero já tem o que mais ninguém tem: **horas reais trabalhadas, autenticadas, com pausas descontadas** (Frente A). Falta juntar duas coisas:

1. **Custo-hora por colaborador** (vencimento + encargos TSU ~23,75% + subsídios proporcionais) — campo sensível, role de acesso próprio (já previsto, doc 08 §7).
2. **Vendas do dia** — do POS (§7) ou inseridas manualmente no MVP.

Com as duas: **% labour cost diário/semanal real** (não estimado), custo por turno, comparação escala planeada vs horas reais, alerta "o labour cost desta semana vai passar os X% se mantiveres a escala". Nenhum Excel compete com dados de picagem autenticada. *[Certain na mecânica; Likely no valor comercial]*

### 5.2 Food cost — fichas técnicas e margem por prato

| Peça | O que é |
|---|---|
| Ingredientes | catálogo com unidade de compra, preço atual, fornecedor |
| Fichas técnicas | receita = ingredientes + quantidades + quebra → **custo por dose** calculado |
| Margem por prato | custo por dose vs preço de venda → margem e rácio, sinalizado quando degrada |
| Atualização de preços | manual no MVP → por fatura (OCR/e-fatura) depois: preço do fornecedor sobe → todas as fichas que o usam recalculam → alerta "a francesinha perdeu 4 p.p. de margem este mês" |
| Inventário periódico | contagem (pode ser tarefa de checklist no kiosk — reutiliza o motor HACCP e a prova autenticada) → consumo teórico vs real → quebra/desvio |

**Nota de arquitetura:** a ficha técnica liga o food cost ao HACCP — o mesmo ingrediente tem alergénios (informação ao consumidor, obrigatória) e temperatura de conservação (checklist). Um catálogo de ingredientes bem desenhado serve os dois módulos. *[Likely]*

### 5.3 O painel do dono ("na palma da mão")

Uma vista mobile-first, para o proprietário, com o dia de hoje:
- Quem está a trabalhar agora (picagens) vs escala prevista
- Tarefas HACCP: feitas / em falta / não conformidades abertas
- Vendas do dia (POS) · labour cost % · alertas de margem
- Anúncios por confirmar, pedidos pendentes (férias, trocas)
- Vera acessível para perguntar ("qual foi o labour cost da semana passada?", "há checklists em falta na loja 2?")

É a materialização da promessa "controlar o negócio na palma da mão" — e só faz sentido construir quando A, B e C alimentam os dados (doc 08 §4 já o diz para o dashboard admin; este é o mesmo princípio, versão mobile do dono).

---

## 6. Módulo: Agentes de AI (o padrão Vera replicado)

A Vera estabeleceu o padrão inegociável: **grounded (só responde de fonte citada ou tabela), nunca autoridade final, humano aprova**. Cada agente novo herda o padrão — muda o domínio e o corpus, não a regra. *[Certain]*

| Agente | Domínio | Corpus/fonte | O que faz | O que NUNCA faz |
|---|---|---|---|---|
| **Vera** (existente em plano) | HACCP | Reg. 852/853, Portaria 1135/95, AHRESP, plano do estabelecimento | Onboarding de checklists, esclarece limites com citação | Inventar limites |
| **Agente de escalas** | Horários | CT (descanso, trabalho noturno, jovens), horas reais, previsão de movimento | Propõe escala que cumpre a lei e o orçamento de labour cost | Publicar sem aprovação humana |
| **Agente de custos** | Food/labour cost | Fichas técnicas, faturas, vendas | Deteta desvios ("o preço do azeite subiu 18%"), responde a perguntas de margem | Alterar preços de venda |
| **Agente de compras** | Aprovisionamento | Consumos, inventário, prazos de entrega | Rascunha encomenda semanal por níveis de stock | Encomendar sem aprovação |
| **Agente RH** | Legislação laboral | CT + contratos-tipo + convenções do setor (AHRESP) | Responde "quantos dias de férias tem direito?", rascunha adendas | Parecer jurídico vinculativo |

Infra: a mesma já decidida (Ollama→vLLM, structured outputs, pgvector no Supabase, camada de abstração de provider). Um agente novo = corpus novo + tabela de autoridade nova + prompt de sistema — não é infra nova. *[Likely]*

---

## 7. Integrações (onde os dados externos entram)

| Integração | Traz | Realidade em PT |
|---|---|---|
| **POS** | vendas por dia/hora/produto → labour cost % e food cost reais | Fragmentado: Zone Soft, Winrest, Rest, Toast é raro. Começar por **1–2 POS dominantes no segmento-alvo** + import manual/CSV como fallback universal. O SAF-T (obrigatório para a AT) é um formato de exportação que quase todos suportam — candidato a via de integração barata *[Likely]* |
| Contabilidade | envio automático de dados de assiduidade para processamento salarial; receção de recibos | Email estruturado/export primeiro; API (Toconline, Moloni, Cegid) depois |
| Fornecedores/faturas | preços reais para o food cost | OCR de fatura ou e-fatura/AT *[Guessing na viabilidade da via AT — verificar]* |
| Prestador de assinatura | validade jurídica dos contratos (§4.2) | Signaturit/Lleida/DocuSign/AMA |
| Push/SMS | notificações ao colaborador | Expo Push (PWA: Web Push) + SMS transacional |

---

## 8. Priorização (valor × esforço × dependências)

| Expansão | Valor p/ dono | Esforço | Depende de | Onda |
|---|---|---|---|---|
| Portal do colaborador (PWA, auth individual) | Alto (desbloqueia tudo) | M | R3 parcial | **1.ª** |
| Notificações de horário + mural com confirmação | Alto | S–M | Portal + horário (R3) | **1.ª** |
| Recibos no perfil + notificação | Alto | S | Portal + bucket (R3) | **1.ª** |
| Assinatura de contratos (prestador) | Alto | M | Portal + documentos (R3) | **2.ª** |
| Labour cost % (vendas manuais) | Alto | S–M | Frente A + custo-hora | **2.ª** |
| Painel do dono (mobile) | Alto | M | A + B + C | **2.ª** |
| Chat / pedidos estruturados | Médio | M | Portal | 3.ª |
| Food cost (fichas técnicas) | Alto | L | catálogo ingredientes | 3.ª |
| Integração POS | Alto | L | labour/food cost | 3.ª |
| Agentes adicionais (escalas, custos) | Médio–Alto | M cada | dados das ondas 2–3 + infra Vera | 4.ª |
| Inventário + agente de compras | Médio | L | food cost | 4.ª |

Leitura: a **1.ª onda é quase toda "portal do colaborador + coisas pequenas em cima"** — é o maior rácio valor/esforço de todo o documento, e é exatamente o que foi pedido (notificações de horário, recibos). A assinatura de contratos vem logo a seguir porque o esforço é sobretudo de integração, não de construção.

---

## 9. Fronteiras que NÃO se movem (mesmo na visão máxima)

1. **Kiosk confinado** a picagem + checklists. O portal do colaborador existe precisamente para o kiosk nunca crescer. *[fechada]*
2. **Biometria nunca.** Nem no portal (nada de login por reconhecimento facial próprio — o FaceID do telemóvel do colaborador é dele, não nosso tratamento). *[fechada]*
3. **NIF/NISS/IBAN** na tabela cifrada com role próprio; o portal do colaborador mostra os *seus*, nunca os de outros. *[fechada]*
4. **AI grounded com aprovação humana** — um número legal nunca vem de palpite de modelo. Aplica-se a todos os agentes, não só à Vera. *[fechada]*
5. **Restaurante = responsável, SaaS = subcontratante.** Cada módulo novo (chat, recibos, assinatura) entra no DPA e no registo de tratamentos — o parecer jurídico tem de acompanhar a expansão, não correr atrás dela. *[Certain]*
6. **Conteúdo clínico e recibos como campos processáveis** continuam fora — recibos entram como documento selado (§4.1), nunca como dados de vencimento consultáveis por quem não tem o role.

---

## 10. Síntese para pitch (o parágrafo)

O CoreVero começa onde a dor é legal — registo de tempos que a ACT aceita e HACCP que a ASAE aceita, ambos com prova autenticada de quem/onde/quando — e cresce até ser o sistema operativo do restaurante: a equipa recebe horários, recibos e assina contratos no telemóvel; o dono vê num só painel quem está a trabalhar, o que falta na cozinha, quanto custa a hora de trabalho de hoje e quanto rende cada prato; e uma equipa de agentes de AI, que só falam com base em fontes citadas, trata do rascunho de escalas, deteta subidas de custos e responde a dúvidas de conformidade — sempre com o humano a aprovar.
