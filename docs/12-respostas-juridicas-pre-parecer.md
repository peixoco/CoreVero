# 12 — Respostas Jurídicas Pré-Parecer (as 8 questões trabalhadas)

> Trabalho preparatório sobre as 8 questões do briefing jurídico (`11-verificacoes-marca-e-juridico.md` §2.4), com textos-tipo redigidos e posições fundamentadas. **Não é parecer jurídico** — é o material que transforma o trabalho do advogado de _redigir_ (caro, lento) em _validar e corrigir_ (barato, rápido). Cada posição leva etiqueta de confiança; as marcadas _[Guessing]_ são exatamente as que o advogado tem de fechar.
> **Regra de retenção adotada (instrução do fundador):** quando várias obrigações legais correm sobre o mesmo registo, aplica-se **o prazo mais alargado**. **Exceção obrigatória:** a foto de atribuição — o art. 5.º/1/e RGPD (minimização/limitação da conservação) impõe o prazo mais _curto_ justificável; "guardar mais por precaução" é, para dados pessoais sem obrigação legal de conservação, em si uma infração. A regra "mais alargado" aplica-se dentro do conjunto de opções defensáveis, nunca para além dele.

---

## Avaliação de conformidade (síntese)

**Veredicto: Prosseguir com condições.** A arquitetura já desenhada (papéis controller/processor limpos, camadas de acesso, relógios de retenção independentes, foto sem matching) está alinhada com o quadro legal. As condições: (1) validação por advogado dos textos-tipo abaixo antes de produção com dados reais de trabalhadores de clientes externos; (2) AIPD-tipo concluída antes do primeiro cliente externo; (3) verificação dos mecanismos de transferência internacional dos subprocessadores (Resend é o ponto fraco — ver Q1).

| Regulação                                   | Relevância                                              | Requisito-chave                                                  |
| ------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------- |
| RGPD arts. 5, 6, 13, 28, 30, 32–36          | Núcleo do produto                                       | Textos-tipo Q1/Q2/Q8; AIPD Q7; medidas técnicas já implementadas |
| Lei 58/2019 (art. 28.º)                     | Enquadra o SaaS como subcontratante para gestão laboral | DPA por cliente (Q1)                                             |
| CT art. 202.º                               | Registo de tempos                                       | 5 anos, com pausas — já no schema                                |
| Reg. 852/2004                               | Prova HACCP                                             | Documentação "adequada" — prazo não fixado no regulamento (Q4)   |
| Cód. Comercial 40.º / LGT 123.º / CIVA 52.º | Documentos com relevância fiscal                        | 10 anos (Q5)                                                     |
| Lei 102/2009 (SST)                          | Aptidão médica                                          | Ficha de aptidão com o empregador; conteúdo clínico fora (Q6)    |
| Regulamento 1/2018 CNPD                     | Lista de tratamentos sujeitos a AIPD                    | Q7 — assumir obrigatória                                         |

---

## Q1 — DPA-tipo (art. 28.º RGPD)

### Posição

Redigir como **anexo de proteção de dados ao contrato de serviço** (não documento avulso), com **autorização geral de subprocessadores + notificação prévia com direito de oposição** — é o padrão de mercado SaaS e o único operacionalmente viável para um solo founder (autorização específica por cliente e por subprocessador é ingerível). _[Certain no requisito legal; Likely no padrão]_

### Elementos obrigatórios (art. 28.º/3 — checklist verificada)

Objeto e duração · natureza e finalidade · tipos de dados · categorias de titulares · obrigações e direitos do responsável · instruções documentadas · confidencialidade do pessoal · medidas art. 32.º · regime de subcontratação · assistência a direitos dos titulares · assistência a violações/AIPD/consulta prévia · devolução ou apagamento no termo · auditoria.

### Esqueleto redigido (para o advogado validar, não redigir)

**ANEXO — ACORDO DE SUBCONTRATAÇÃO DE TRATAMENTO DE DADOS (art. 28.º RGPD)**

**1. Partes e papéis.** O Cliente ("Restaurante") é o **responsável pelo tratamento**; a Peixoco, Lda. ("CoreVero") é o **subcontratante**, nos termos do art. 4.º/7 e /8 do RGPD e do art. 28.º da Lei n.º 58/2019.

**2. Objeto, natureza e finalidade.** Tratamento de dados pessoais de trabalhadores do Cliente estritamente necessário à prestação do serviço CoreVero: (a) registo de tempos de trabalho (art. 202.º CT); (b) registo de conformidade HACCP com atribuição autenticada (Reg. (CE) 852/2004); (c) gestão administrativa associada. Duração: a do contrato de serviço.

**3. Categorias de titulares e de dados.** Titulares: trabalhadores do Cliente; utilizadores administradores. Dados: identificação (nome, código interno), registos de tempos (entradas, saídas, pausas, momento e local), fotografia de atribuição no momento do registo, registos de conformidade HACCP, dados de contacto profissional; quando o módulo RH estiver ativo: dados fiscais/contributivos (NIF, NISS, IBAN) e documentos contratuais, em camada cifrada com acesso por perfil restrito. **Não são tratados dados biométricos:** a fotografia destina-se a verificação por revisão humana e o CoreVero não realiza, nem realizará, reconhecimento facial automático (Considerando 51 RGPD).

**4. Instruções.** O CoreVero trata os dados exclusivamente segundo instruções documentadas do Cliente, incluindo as configurações efetuadas na plataforma (nomeadamente prazos de conservação parametrizados), salvo obrigação legal em contrário — caso em que informa o Cliente antes do tratamento, exceto se a lei o proibir.

**5. Confidencialidade.** Todas as pessoas autorizadas a tratar dados estão vinculadas a dever de confidencialidade contratual ou legal.

**6. Segurança (art. 32.º).** Medidas implementadas: alojamento na União Europeia (região AWS eu-west-3, Paris); isolamento multi-tenant com Row-Level Security ao nível da base de dados; cifragem em trânsito e em repouso; cifragem adicional ao nível da coluna para dados fiscais; controlo de acessos por perfil (o dispositivo de registo — kiosk — não acede a dados administrativos, fiscais ou documentais); registos imutáveis (append-only) com correção por novo registo; expiração automática de fotografias por tarefa agendada; registo de acessos.

**7. Subcontratantes ulteriores.** O Cliente autoriza, de forma geral, o recurso aos subcontratantes ulteriores listados no Apêndice 1. O CoreVero notifica o Cliente com [30] dias de antecedência de qualquer adição ou substituição, podendo o Cliente opor-se por motivos razoáveis e fundamentados; na falta de acordo, o Cliente pode resolver o contrato quanto ao serviço afetado. O CoreVero impõe a cada subcontratante ulterior, por escrito, obrigações equivalentes às deste Anexo e permanece integralmente responsável perante o Cliente.

**Apêndice 1 — Subcontratantes ulteriores (à data):**
| Entidade | Serviço | Localização do tratamento | Mecanismo de transferência |
|---|---|---|---|
| Supabase, Inc. | Base de dados, autenticação, armazenamento | AWS eu-west-3 (Paris, UE) | Dados em repouso na UE; DPA Supabase com Cláusulas Contratuais-Tipo (2021) para acessos de suporte a partir de país terceiro _[Likely — confirmar DPA Supabase em vigor]_ |
| Amazon Web Services EMEA SARL | Infraestrutura (via Supabase) | eu-west-3 (Paris, UE) | Dados na UE; AWS certificada no EU-US Data Privacy Framework para casos residuais _[Likely]_ |
| Resend, Inc. | Envio de email transacional/notificações | **EUA** _[Guessing — verificar região e DPA da Resend; ponto fraco, ver nota]_ | CCT/DPF — **a confirmar** |
| Stripe Payments Europe, Ltd. | Faturação (futuro) | UE/EUA | DPF + CCT (Stripe é certificada DPF) _[Likely]_ |

> **Nota crítica sobre a Resend:** é o único subprocessador cuja localização de tratamento não está confirmada como UE. Os emails de notificação contêm dados pessoais (nome do trabalhador, não conformidades). **Ação antes do primeiro cliente externo:** confirmar se a Resend oferece região UE ou DPA com CCT; se não, avaliar alternativa com residência UE (ex.: envio via provedor com data residency europeia). O advogado deve validar o mecanismo escolhido. _[Certain na necessidade de verificação]_

**8. Assistência ao responsável.** O CoreVero presta assistência razoável ao Cliente: (a) na resposta a pedidos de exercício de direitos dos titulares (arts. 12.º–23.º), através das funcionalidades da plataforma e, subsidiariamente, de apoio direto; (b) no cumprimento das obrigações dos arts. 32.º a 36.º, incluindo AIPD e consulta prévia, disponibilizando a documentação técnica e a AIPD-tipo referida na cláusula 11.

**9. Violações de dados pessoais.** O CoreVero notifica o Cliente **sem demora injustificada e, em qualquer caso, no prazo máximo de [48] horas** após tomar conhecimento de uma violação de dados pessoais que afete dados tratados por conta do Cliente, por email para o contacto designado, com: natureza da violação, categorias e número aproximado de titulares e registos afetados, consequências prováveis, medidas adotadas ou propostas. O CoreVero coopera com o Cliente para permitir o cumprimento do prazo de 72 horas do art. 33.º e documenta todas as violações. A notificação ao Cliente não constitui admissão de responsabilidade.

**10. Termo do contrato.** No termo, o Cliente escolhe entre devolução (exportação em formato estruturado) ou apagamento dos dados; o apagamento ocorre no prazo de [30] dias após a escolha ou, na ausência de escolha, [90] dias após o termo — **com exceção** dos registos cuja conservação seja exigida por lei ao próprio Cliente e que este não tenha exportado, os quais são conservados bloqueados pelo período legal remanescente ou devolvidos mediante pedido. _[Likely — o advogado deve afinar o regime de dados “órfãos” pós-termo, é a cláusula mais delicada do documento]_

**11. AIPD-tipo.** O CoreVero disponibiliza ao Cliente uma avaliação de impacto sobre a proteção de dados relativa ao funcionamento-padrão da plataforma (art. 35.º/1, parte final), que o Cliente adota e assume como sua, complementando-a com as especificidades do seu contexto.

**12. Auditoria.** O Cliente pode solicitar, uma vez por ano ou mediante causa justificada, informação demonstrativa do cumprimento deste Anexo; auditorias presenciais carecem de pré-aviso de [30] dias, não podem perturbar a operação e correm por conta do Cliente. O CoreVero pode satisfazer o pedido por relatórios de terceiros quando existam.

### Risco (matriz do skill de avaliação)

| Item                                              | Sev. | Prob. | Score         | Ação                                                  |
| ------------------------------------------------- | ---- | ----- | ------------- | ----------------------------------------------------- |
| Resend sem mecanismo de transferência confirmado  | 3    | 4     | **12 — ALTO** | Resolver antes do 1.º cliente externo                 |
| DPA sem validação de advogado em produção externa | 4    | 3     | **12 — ALTO** | Validação é bloqueante de R5, não de pilotos próprios |
| Cláusula de dados pós-termo mal desenhada         | 3    | 3     | 9 — MÉDIO     | Afinar com advogado (cl. 10)                          |

---

## Q2 — Texto de informação aos trabalhadores (art. 13.º)

### Posição

Documento **de uma página**, entregue no onboarding e afixado junto ao kiosk, em linguagem simples. O responsável é o restaurante — o texto-tipo traz campos [entre parênteses retos] que cada cliente preenche. _[Certain na estrutura exigida pelo art. 13.º]_

### Texto redigido

---

**INFORMAÇÃO SOBRE O TRATAMENTO DOS SEUS DADOS PESSOAIS**
_(art. 13.º do Regulamento Geral sobre a Proteção de Dados)_

**Quem é o responsável pelos seus dados?**
[Denominação social do restaurante], NIPC [•], com sede em [•], contacto para questões de proteção de dados: [email]. Os dados são tratados na plataforma CoreVero, operada pela Peixoco, Lda. na qualidade de subcontratante, com alojamento na União Europeia.

**Que dados tratamos e para quê?**

1. **Registo de tempos de trabalho** — horas de entrada, saída e pausas, registadas no equipamento partilhado com o seu código pessoal. _Finalidade:_ cumprir a obrigação legal de registo de tempos de trabalho (art. 202.º do Código do Trabalho). _Base legal:_ obrigação jurídica (art. 6.º/1/c RGPD).
2. **Fotografia no momento do registo** — captada no equipamento a cada registo. _Finalidade:_ confirmar, por verificação humana, que foi o próprio a registar, protegendo-o contra registos feitos por terceiros em seu nome. **Não é utilizada tecnologia de reconhecimento facial nem qualquer tratamento biométrico** — a fotografia serve apenas para conferência visual por pessoa autorizada em caso de dúvida ou reclamação. _Base legal:_ interesse legítimo do empregador na fiabilidade do registo (art. 6.º/1/f), ponderado com os seus direitos. É conservada por período curto (ver abaixo) e depois eliminada automaticamente.
3. **Registos de segurança alimentar (HACCP)** — quando preenche verificações de higiene e segurança alimentar, fica registado quem, quando e onde. _Finalidade:_ prova de conformidade exigida pela legislação alimentar (Reg. (CE) 852/2004), sujeita a inspeção da ASAE. _Base legal:_ obrigação jurídica (art. 6.º/1/c).
4. **Dados de gestão laboral** — identificação, categoria, horário, férias e, para processamento salarial, NIF, NISS e IBAN. _Base legal:_ execução do contrato de trabalho (art. 6.º/1/b) e obrigações legais fiscais e contributivas (art. 6.º/1/c). Os dados fiscais são guardados de forma cifrada, com acesso restrito, e nunca são visíveis no equipamento de registo.
   **Quem pode aceder aos seus dados?**
   Pessoas autorizadas da [empresa] (gestão/administração, segundo perfis de acesso); o contabilista da empresa, para processamento salarial; autoridades com competência legal (ACT, ASAE, Autoridade Tributária, Segurança Social), quando o exijam; e os prestadores técnicos que operam a plataforma (Peixoco, Lda. e os seus subcontratantes de alojamento e envio de notificações, vinculados por contrato nos termos do art. 28.º RGPD). Os seus dados não são vendidos nem usados para publicidade.

**Por quanto tempo?**
| Categoria | Prazo |
|---|---|
| Registo de tempos de trabalho | 5 anos (obrigação legal) |
| Fotografia de registo | [90] dias, eliminação automática |
| Registos HACCP | [5] anos |
| Dados fiscais e documentos contratuais | 10 anos após a cessação (obrigação legal) |
| Ficha de aptidão médica / certificados | Duração do contrato + [5] anos |

**Os seus direitos.** Pode pedir o acesso aos seus dados, a sua retificação, o apagamento (nos limites das obrigações legais de conservação), a limitação do tratamento e opor-se ao tratamento baseado em interesse legítimo, contactando [email]. Tem ainda o direito de apresentar reclamação à Comissão Nacional de Proteção de Dados (www.cnpd.pt). O fornecimento dos dados das finalidades 1, 3 e 4 é exigência legal ou contratual — sem eles não é possível manter a relação laboral nos termos da lei. Não são tomadas decisões exclusivamente automatizadas sobre si.

---

_[Likely na base legal da foto: art. 6.º/1/f com ponderação é a posição defensável; alternativa é 6.º/1/c por acessoriedade ao art. 202.º. É a questão jurídica mais fina do documento — o advogado escolhe entre as duas e a escolha condiciona o direito de oposição. Assinalada como decisão dele.]_

---

## Q3 — Retenção da foto de atribuição

**Proposta: 90 dias** — o mais alargado do conjunto que pediste (30/60/90), e o teto do defensável. Fundamentação para o advogado validar:

- A finalidade (verificação humana em caso de contestação de picagem) esgota-se no ciclo de conferência salarial. 90 dias cobre **três fechos de processamento salarial** — qualquer reclamação razoável de picagem surge dentro deste horizonte. _[Likely]_
- Acima disso, a foto deixa de ter necessidade demonstrável e passa a passivo RGPD: milhares de imagens de trabalhadores sem finalidade ativa. A CNPD lê "por precaução" como violação do art. 5.º/1/e. _[Certain no princípio]_
- **Mecanismo de exceção** (isto sim, a precaução certa): se uma picagem específica entrar em contestação formal dentro dos 90 dias, a foto **dessa picagem** é marcada como "em litígio" e fica excluída da purga até resolução (base: art. 17.º/3/e — defesa em processo). Precaução cirúrgica em vez de retenção geral. _[Likely]_
- Implementação: `foto_retencao_dias` configurável por tenant (default 90), flag `em_litigio` na `verificacao` que o job de expiração respeita.
  **Pergunta residual ao advogado:** validar 90 + mecanismo de litígio; confirmar se o prazo de reclamação de créditos salariais correntes aconselha alinhamento diferente.

---

## Q4 — Retenção da prova HACCP

**Facto central:** o Reg. 852/2004 (art. 5.º/2/g e /4/c) exige documentação e registos "adequados" e a sua conservação "durante um período adequado" — **não fixa prazo numérico**. _[Certain]_ A definição do prazo cai no plano HACCP do operador e na expectativa prática da inspeção.

**Proposta (regra "mais alargado" aplicada — aqui pode ser, porque o registo de conformidade sem foto é prova documental, não dado pessoal sensível): default de 5 anos**, configurável por tenant, mínimo técnico de 2:

- 5 anos alinha o relógio HACCP com o relógio laboral (art. 202.º) — os dois tipos de registo do produto expiram em conjunto, simplificando a arquitetura e eliminando o cenário "a ASAE pede um registo que já purgámos". _[Likely]_
- A prática setorial europeia varia entre "vida útil do produto + margem" e 2–5 anos; nenhuma fonte indexada no projeto fixa número estatutário para restauração. _[Certain na ausência de número estatutário nas fontes; Guessing na prática exata da ASAE]_
- Nota RGPD: os registos HACCP contêm dados pessoais (quem verificou). 5 anos justifica-se pela finalidade de prova perante inspeção — fundamentar isto no registo de tratamentos (Q8).
  **Pergunta residual:** confirmar com o advogado **e** com consultor de segurança alimentar a expectativa concreta da ASAE; o campo já é configurável, portanto a resposta não bloqueia código.

---

## Q5 — Contrato pós-cessação: 5 vs 10 anos

**Fechado em 10 anos** — a tua regra e a recomendação preliminar do doc 06 coincidem, e a fundamentação é sólida:

- O contrato contém a retribuição → documento com relevância fiscal/contributiva → Cód. Comercial art. 40.º / LGT art. 123.º / CIVA art. 52.º puxam para 10. _[Certain na relevância fiscal; Likely na conclusão de subsunção]_
- Cobre por absorção todos os prazos menores (contraordenações laborais e SS: 5; créditos laborais: 1 após cessação; impugnação de despedimento: 60 dias/6 meses/1 ano).
- Implementação: relógio do bucket `documentos_colaborador` = cessação + 10 anos.
  **Pergunta residual:** apenas confirmação formal — é o item mais barato do parecer.

---

## Q6 — Aptidão médica e certificado de manipulador pós-cessação

**Proposta: duração do contrato + 5 anos** (o mais alargado defensável):

- A ficha de aptidão (apto/não apto + datas — **nunca** conteúdo clínico, que fica na medicina do trabalho) é o documento que o empregador exibe à ACT; o prazo de prescrição das contraordenações SST (5 anos) é o relógio de risco relevante. Alinhar com +5 cobre-o. _[Likely]_
- O certificado de manipulador é prova de pré-requisito HACCP → alinhar com o relógio HACCP (5 anos) dá o mesmo número por caminho independente — coerência que reforça a proposta. _[Likely]_
- Não há relevância fiscal que justifique 10; esticar além do risco real recria o problema da minimização (a ficha de aptidão, mesmo sem conteúdo clínico, é dado pessoal relativo a saúde em sentido lato). _[Likely]_
  **Pergunta residual:** o número +5 é a posição menos ancorada em norma expressa de todo o documento — _[Guessing controlado]_ — validação obrigatória.

---

## Q7 — AIPD: obrigatoriedade e AIPD-tipo

**Posição: assumir obrigatória e fazê-la — não gastar honorários a discutir se é evitável.** Fundamentos:

- O Regulamento 1/2018 da CNPD (lista do art. 35.º/4) sujeita a AIPD tratamentos que envolvam **monitorização sistemática de titulares vulneráveis — trabalhadores incluídos** — mesmo em pequena escala; a FAQ da CNPD sobre contexto laboral confirma-o expressamente para sistemas de controlo de assiduidade. O CoreVero capta imagem de trabalhadores em cada picagem, sistematicamente, com registo de local e hora. A subsunção é quase direta. _[Likely, próximo de Certain]_
- Mesmo que um advogado construísse o argumento de escape, o custo da AIPD é inferior ao custo do argumento — e a AIPD-tipo é **ativo comercial** (o cliente-restaurante recebe a sua obrigação do art. 35.º pré-cumprida, assumindo-a nos termos da parte final do art. 35.º/1, mecanismo que a própria CNPD reconhece).
  **Estrutura da AIPD-tipo (a preparar; o advogado valida):**

1. Descrição sistemática do tratamento (fluxos picagem/HACCP, camadas de acesso, diagrama).
2. Necessidade e proporcionalidade: porquê foto e não biometria (comparação expressa com o regime do art. 28.º/6 Lei 58/2019 que se evita); porquê PIN server-side; minimização por design.
3. Riscos para os titulares: acesso indevido à foto; uso da foto para fim diverso; pressão de vigilância; erro de atribuição. Avaliação sev./prob. de cada um.
4. Medidas: RLS multi-tenant, kiosk confinado, retenção 90 dias com purga automática, append-only, cifragem de dados fiscais, ausência de matching facial (compromisso contratual — cláusula 3 do DPA).
5. Conclusão de risco residual e condições de revisão (qualquer alteração ao fluxo de captura reabre a AIPD).
   **Regra de arquitetura que a AIPD sela:** a proibição de reconhecimento facial automático deixa de ser nota de doc e passa a **compromisso contratual e pressuposto da AIPD** — adicioná-la a qualquer versão futura invalida a avaliação e reabre todo o quadro (art. 9.º, AIPD nova, provável consulta prévia). _[Certain]_

---

## Q8 — Registos de tratamento (art. 30.º)

**Facto prévio:** a isenção do art. 30.º/5 (<250 trabalhadores) **não se aplica** — só vale para tratamentos ocasionais, e este é o núcleo permanente do negócio. Ambos os registos são obrigatórios. _[Certain]_

**Registo A — modelo-tipo para o cliente (responsável), art. 30.º/1** — entregue pré-preenchido com o produto, o cliente completa os campos [•]:
| Campo | Conteúdo pré-preenchido |
|---|---|
| Responsável | [cliente] · Contacto: [•] |
| Finalidades | Registo de tempos (art. 202.º CT) · Prova HACCP (Reg. 852/2004) · Gestão laboral/salarial |
| Categorias de titulares | Trabalhadores |
| Categorias de dados | Identificação; registos de tempos; fotografia de atribuição; registos HACCP; dados fiscais (NIF/NISS/IBAN); documentos contratuais; aptidão médica (status/datas) |
| Destinatários | Contabilista [•]; ACT/ASAE/AT/SS quando exigido; Peixoco Lda. (subcontratante) e ulteriores (Apêndice 1 do DPA) |
| Transferências p/ países terceiros | Nenhuma no fluxo principal (alojamento UE); residual via subprocessadores — ver Apêndice 1 e mecanismos |
| Prazos | Tabela de retenções (a mesma do texto art. 13.º — fonte única, gerada da configuração do tenant) |
| Medidas de segurança | Descrição das medidas da cláusula 6 do DPA |

**Registo B — próprio da Peixoco (subcontratante), art. 30.º/2:** nome e contactos do subcontratante; identificação de cada responsável por conta de quem trata (= lista de clientes — gerável da tabela `empresa`); categorias de tratamentos efetuados por conta de cada um; transferências; medidas de segurança. **Nota de implementação:** os dois registos devem ser _gerados da configuração real_ (tenants, retenções parametrizadas, subprocessadores) e não mantidos à mão — um registo art. 30.º desatualizado é pior perante a CNPD do que nenhum, porque documenta a desconformidade. _[Likely]_

---

## Mapa de retenções consolidado (a tabela única que o advogado carimba)

| #   | Categoria                          | Prazo proposto                | Regra aplicada                            | Confiança            | Norma-âncora                          |
| --- | ---------------------------------- | ----------------------------- | ----------------------------------------- | -------------------- | ------------------------------------- |
| 1   | Registo de tempos                  | **5 anos**                    | Legal fixo                                | [Certain]            | CT art. 202.º/4                       |
| 2   | Foto de atribuição                 | **90 dias** + exceção litígio | Mínimo justificável (exceção à tua regra) | [Likely]             | RGPD 5.º/1/e; 17.º/3/e                |
| 3   | Prova HACCP (sem foto)             | **5 anos** (config., mín. 2)  | Mais alargado defensável                  | [Likely]             | Reg. 852/2004 art. 5.º (prazo aberto) |
| 4   | Dados fiscais (NIF/NISS/IBAN)      | **10 anos**                   | Legal fixo                                | [Certain]            | Cód. Com. 40.º; LGT 123.º; CIVA 52.º  |
| 5   | Contrato + adendas                 | **cessação + 10 anos**        | Mais alargado (fiscal absorve laboral)    | [Likely]             | idem + CT                             |
| 6   | Aptidão médica / cert. manipulador | **cessação + 5 anos**         | Mais alargado defensável                  | [Guessing no número] | Lei 102/2009; prescrição SST          |

Seis relógios, seis jobs de expiração independentes (o doc 06 previa quatro; a separação foto/HACCP/aptidão afina para seis). Todos configuráveis; os defaults acima.

---

## O que fica para o advogado (reduzido ao osso)

1. Validar/corrigir o DPA-tipo (Q1), com atenção às cláusulas 7, 9 e 10.
2. Escolher a base legal da foto — 6.º/1/f vs 6.º/1/c (Q2) — e carimbar o texto art. 13.º.
3. Carimbar a tabela de retenções (acima), com foco nos itens 3 e 6.
4. Validar a AIPD-tipo quando redigida (Q7).
5. Confirmar o desenho dos dois registos art. 30.º (Q8).
   Com este documento anexo ao briefing, o âmbito do parecer passa de "conceber o quadro de conformidade" para "rever seis documentos e fechar quatro números" — é essa a diferença entre 2 e 8 semanas de calendário. _[Likely]_
