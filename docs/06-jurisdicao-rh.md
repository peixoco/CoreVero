# 06 — Jurisdição e Gestão de Dados RH

> Que regimes legais se aplicam quando o produto passa a incluir gestão de RH (picagem, horas, férias, horário, ficha do colaborador), quem é responsável por quê, que dados se guardam, por quanto tempo e com que separação de acesso.
> Princípio: o produto é **ferramenta**; o **restaurante-cliente é o responsável** pelo tratamento. A picagem é, em simultâneo, **prova HACCP** e **registo legal de tempos de trabalho**.
> Documentos relacionados: `00-contexto-projeto.md`, `01-arquitetura-bd.md`, `02-stack-e-padroes.md`, `04-levantamento-haccp.md`.

---

## 1. A pilha de jurisdição (não há um regime — há quatro)

O momento em que se adicionam horas, férias e horário acende o **regime laboral**, que os documentos anteriores (focados em HACCP + RGPD) não cobriam. Passam a existir **duas inspeções com poder de "mostra-me agora"** — ASAE e ACT — cada uma com o seu prazo de retenção e a sua noção de "registo válido".

| Regime                | Instrumento                                              | Autoridade                | O que obriga                                                                   | Prazo-chave                   |
| --------------------- | -------------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------ | ----------------------------- |
| Proteção de dados     | RGPD (2016/679) + Lei 58/2019                            | **CNPD**                  | _como_ se tratam/guardam dados de pessoas (minimização, segurança, informação) | mínimo necessário             |
| Direito laboral       | Código do Trabalho (Lei 7/2009) + SST (Lei 102/2009)     | **ACT**                   | _o que_ se regista (tempos, horário, férias) e exibir de imediato              | **registo de tempos: 5 anos** |
| Segurança alimentar   | Reg. (CE) 852/2004                                       | **ASAE**                  | prova de conformidade HACCP                                                    | longa (ver `01`/`04`)         |
| Fiscal / contributivo | Cód. Comercial art. 40.º; LGT art. 123.º; CIVA art. 52.º | **AT / Segurança Social** | conservação de documentos fiscais e de remuneração                             | **10 anos**                   |

---

## 2. Papéis: quem é o responsável pelo tratamento

A questão estrutural que define todas as obrigações de retenção e informação:

- **Restaurante-cliente = responsável pelo tratamento (controller).** Decide finalidade, base legal, prazos de retenção (dentro dos mínimos legais) e informa os trabalhadores.
- **O SaaS = subcontratante (processor).** Fornece o sistema pré-configurado + **contrato de subcontratação (art. 28.º RGPD / DPA)**. **Não decide retenções — fornece-as configuráveis.**
  Pontos de apoio legal:
- A base legal para dados de trabalhadores **não é o consentimento** (o desequilíbrio empregador-trabalhador retira-lhe validade). É a **execução do contrato** ou a **obrigação legal**.
- O **art. 28.º da Lei 58/2019** abrange expressamente o tratamento efetuado por **subcontratante em nome do empregador**, para gestão das relações laborais, ao abrigo de contrato de prestação de serviços e com garantias de sigilo. É o enquadramento exato deste produto.
  > Na fase de teste (restaurante próprio) o promotor acumula os dois papéis — responsável (enquanto restaurante) e subcontratante (enquanto SaaS). Manter os papéis **limpos na arquitetura desde já**, pela mesma razão que se mantém o multi-tenant com um só tenant: converter depois é o erro caro.

---

## 3. Fronteira kiosk vs admin (decisão fechada)

| Camada    | Faz                                                                                             | Nunca faz                                                        |
| --------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Kiosk** | Só **picagem (horas)** + **registos de checklist HACCP**. Identifica por código + foto.         | Não lê nem escreve dados RH, fiscais, contratuais ou de aptidão. |
| **Admin** | Tudo o resto: ficha do colaborador, dados fiscais, documentos, aptidão médica, férias, horário. | —                                                                |

Consequência de segurança: a superfície de exposição do kiosk é mínima. Uma fuga ao nível do kiosk **não** expõe dados de RH nem fiscais — esses vivem noutra camada, com outro controlo de acesso.

---

## 4. Catálogo de dados — obrigação, retenção e gestão por categoria

| Categoria                                       | Finalidade                                            | Base legal                                | Quem detém                                                           | Retenção                                      | Camada      | Como gerir                                                                  |
| ----------------------------------------------- | ----------------------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------- | --------------------------------------------- | ----------- | --------------------------------------------------------------------------- |
| Identidade kiosk (nome curto, área, PIN, ativo) | Funcionamento app + filtra checklists por zona        | Execução do contrato                      | SaaS (em nome do cliente)                                            | Enquanto ativo; definir prazo pós-desativação | Kiosk       | Sem dados sensíveis                                                         |
| Nome completo + função                          | Prova ASAE / relatórios; identificação na prova       | Obrigação legal (HACCP)                   | Restaurante                                                          | Alinhar com a prova HACCP/laboral             | Admin       | Exportação/relatório                                                        |
| Picagem: entrada, saída, **pausas/intervalos**  | **Registo legal de tempos (CT art. 202.º)**           | Obrigação legal                           | Restaurante (empregador)                                             | **5 anos**                                    | Kiosk→prova | **Inalterável; exibível à ACT de imediato; exportável**                     |
| Foto de atribuição                              | Atribuição por revisão humana (não biometria)         | Execução do contrato / interesse legítimo | Restaurante                                                          | **Curta, purgável**                           | Kiosk       | Job de expiração; separada da prova                                         |
| Prova de conformidade HACCP                     | Inspeção ASAE                                         | Obrigação legal                           | Restaurante                                                          | Longa (confirmar c/ resp. seg. alimentar)     | Admin       | Append-only; exportável                                                     |
| Datas de contrato (início/fim)                  | Gestão laboral; automatiza `ativo=false`              | Execução do contrato                      | Restaurante                                                          | Durante contrato + margem                     | Admin       | —                                                                           |
| Contacto (1 canal: tel **ou** email)            | Notificações / contacto                               | Execução do contrato                      | Restaurante                                                          | Enquanto necessário                           | Admin       | Finalidade isolada                                                          |
| Aptidão médica (data, validade, apto/inapto)    | Controlo SST (Lei 102/2009)                           | Obrigação legal                           | Clínica detém o **conteúdo**; restaurante detém o **resultado**      | Durante contrato + margem                     | Admin       | **Só status + datas, sem notas clínicas**; alerta de expiração              |
| Cert. manipulador de alimentos (validade)       | Pré-requisito HACCP (formação)                        | Obrigação legal (HACCP)                   | Restaurante                                                          | Durante validade + prova                      | Admin       | Campo de formação; alerta de expiração                                      |
| **NIF / NISS / IBAN**                           | Pagamento de salários / obrigação fiscal-contributiva | Obrigação legal                           | Restaurante (resp.); contabilista (subcontratante); SaaS detém cópia | **10 anos**                                   | Admin       | **Tabela separada, role de pagamentos, cifrado em repouso, nunca no kiosk** |
| **Documentos: contrato assinado + adendas**     | Prova da relação laboral                              | Obrigação legal                           | Restaurante                                                          | **5 anos mín. / até 10 anos** (ver §5)        | Admin       | **Bucket próprio, admin-only, cifrado**                                     |

---

## 5. Os relógios de retenção (quatro, a correr em paralelo sobre a mesma pessoa)

Isto é requisito de arquitetura, não decisão caso a caso: **cada categoria tem o seu job de expiração independente.**

1. **Registo de tempos (picagem)** → **5 anos** (CT art. 202.º, n.º 4). A violação é contraordenação grave. _[Certain]_
2. **Foto de atribuição** → **curta e purgável** (minimização RGPD). Prazo concreto a definir com jurista. _[a confirmar]_
3. **Prova de conformidade HACCP** → **longa** (inspeção ASAE). Prazo a fechar com o responsável de segurança alimentar. _[a confirmar]_
4. **Dados fiscais + documentos com relevância fiscal/retributiva** (NIF/NISS/IBAN, contrato com vencimento) → **10 anos** (Cód. Comercial art. 40.º; LGT art. 123.º; CIVA art. 52.º). _[Certain]_
   Casos mistos:

- **Contrato + adendas:** mínimo **5 anos** pós-cessação (prescrição de contraordenações laborais e de Segurança Social = 5 anos; créditos laborais prescrevem 1 ano após cessação; impugnação de despedimento até 60 dias / 6 meses / 1 ano). Como o contrato contém retribuição, ganha relevância fiscal → na prática recomenda-se alinhar com os **10 anos**. Fechar no parecer jurídico. _[Likely]_
- **Aptidão médica / certificados:** durante o contrato + margem pós-cessação. _[a confirmar]_

---

## 6. Pasta do colaborador — armazenamento de documentos

- **Guarda:** contrato de trabalho assinado + adendas/aditamentos de qualquer natureza.
- **NÃO guarda:** recibos de vencimento — ficam com a **contabilista** (não duplicar no SaaS).
  Nuance importante: o contrato contém precisamente os dados que se minimizam enquanto _campos_ (NIF, morada, vencimento base). Mas aqui entram como **documento selado** (prova da relação laboral), **não** como campos consultáveis/processáveis. Finalidade e tratamento são diferentes — e por isso a gestão também:

- **Bucket separado** do bucket de fotos.
- **Acesso só admin**, com role próprio (nunca o kiosk; nunca um gestor que só faça HACCP).
- **Cifrado em repouso.**
- **Retenção própria** (ver §5), com job de expiração dedicado.

---

## 7. O que fica DE FORA — e porquê (exclusões deliberadas, não esquecimentos)

- **Recibos de vencimento** → com a contabilista. Não se duplicam no SaaS.
- **Conteúdo clínico / ficha médica** → fica na clínica de medicina no trabalho. É **categoria especial (art. 9.º RGPD)**; o SaaS guarda apenas data + validade + apto/inapto. Guardar o motivo de um "apto com restrições" reabriria o art. 9.º.
- **Biometria / reconhecimento facial** → **nunca**. Dispararia o art. 9.º RGPD + notificação prévia à CNPD + parecer da comissão de trabalhadores + destruição no fim do contrato. A foto é **atribuição por revisão humana**, não identificação biométrica. (Ver `00` §6.)
- **Dados fiscais não necessários ao pagamento** (ex.: agregado familiar/IRS, se a contabilista os trata) → fora. Minimização.

---

## 8. Consequências de implementação (schema)

1. **`picagem` tem de capturar pausas/intervalos**, não só `entrada`/`saida` — o art. 202.º, n.º 2 exige as interrupções para apurar horas por dia e por semana. Sem isto, a picagem não satisfaz o registo legal de tempos.
2. **Registo de tempos inalterável (append-only) + exportável** (PDF/CSV) para consulta imediata da ACT.
3. **Tabela separada `trabalhador_dados_fiscais`** (NIF/NISS/IBAN): RLS + role de pagamentos, cifragem ao nível da coluna (art. 32.º RGPD).
4. **Bucket `documentos_colaborador`** (contrato + adendas): admin-only, cifrado, retenção própria.
5. **Campos de aptidão médica e certificado de manipulador** como status + datas, com **alertas de expiração**.
6. **Quatro jobs de expiração independentes** — um por relógio de retenção (§5).
7. **Mapas que o produto deve poder gerar:** mapa de horário de trabalho e mapa de férias (exigência e formato exatos a confirmar com jurista laboral).

---

## 9. Decisões fechadas vs a confirmar

**Fechadas:**

- Restaurante-cliente = responsável; SaaS = subcontratante (+ DPA por cliente).
- Base legal dos dados de trabalhadores = obrigação legal / execução do contrato (não consentimento).
- Kiosk confinado a picagem + checklist; tudo o resto é admin.
- Separação de camadas: dados fiscais e documentos fora do kiosk, em tabela/bucket próprios, cifrados, com role dedicado.
- Recibos de vencimento ficam com a contabilista; o SaaS guarda contrato + adendas.
  **A confirmar (parecer jurídico RGPD + laboral — workstream paralelo):**
- Prazos exatos: retenção da prova HACCP; retenção do contrato pós-cessação (5 vs 10 anos); margem pós-cessação para aptidão médica e foto.
- Exigência e formato dos mapas de horário e de férias.
- Texto de informação aos trabalhadores (art. 13.º RGPD) e DPA-tipo a apresentar aos clientes.
  > **Disclaimer:** levantamento informativo, não parecer jurídico. Os prazos marcados _[a confirmar]_ / _[Likely]_ devem ser fechados pelo jurista RGPD e por apoio laboral antes de produção com dados reais de trabalhadores. As referências legais citadas (CT art. 202.º, Lei 58/2019 art. 28.º, Cód. Comercial art. 40.º, CIVA art. 52.º) servem de ponto de partida para essa validação.
