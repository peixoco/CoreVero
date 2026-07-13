# 04 — Levantamento de Controlos HACCP (Restaurante) — versão fundamentada

> Inventário dos controlos a monitorizar, com **fonte e estatuto de cada limite**, estruturado para mapear em `checklist_template` (grupo) + `checklist_item` (linha).
> Substitui a versão anterior de valores indicativos: os números abaixo são extraídos das fontes que o utilizador indexou.

---

## 1. Hierarquia de fontes (regra de governação)

A mesma grandeza pode ter valores diferentes em fontes diferentes. Regra:

**Lei > Código de boas práticas > Plano do estabelecimento — e nunca abaixo do mínimo legal.**

- **Lei** — vinculativa e universal (Portaria 1135/95; Reg. (CE) 853/2004).
- **Código de boas práticas** (AHRESP, reconhecido pela DGAV) — referência; adotá-lo corretamente é, para estabelecimentos até 10 trabalhadores, uma rota de conformidade que dispensa a aplicação dos princípios HACCP da legislação.
- **Plano HACCP do estabelecimento** — o valor operativo para aquele cliente; pode ser mais estrito, nunca menos que o mínimo legal.
  Regra do RAG: a AI **cita a fonte** de cada limite e o seu estatuto; onde as fontes divergem, apresenta ambas e remete o desempate para o plano do estabelecimento; onde o corpus é omisso, diz que não sabe — **nunca inventa**.

**Decisão adotada:** o código de referência por defeito é o **Código de Boas Práticas da AHRESP** (cozedura/reaquecimento/conservação a quente ≥ 65 °C; refrigeração 0–7 °C; arrefecimento até 5 °C em ≤ 2 h; congelados ≤ −12 °C / ultracongelados ≤ −18 °C). **Exceção obrigatória:** para produtos de origem animal, os limites do Reg. 853/2004 prevalecem (ex.: congelados ≤ −18 °C, pescado ≈ 0 °C); o óleo segue a Portaria 1135/95. Nenhum item desce abaixo do mínimo legal.

---

## 2. Pontos Críticos de Controlo (PCC) — numéricos, com ação corretiva

| Controlo                            | Tipo     | Unidade    | Limite                                     | Fonte            | Estatuto    |
| ----------------------------------- | -------- | ---------- | ------------------------------------------ | ---------------- | ----------- |
| Confeção (interior)                 | numérico | °C         | **≥ 65 °C**                                | Código AHRESP    | Boa prática |
| Reaquecimento (interior)            | numérico | °C         | **≥ 65 °C** (abaixo: eliminar)             | Código AHRESP    | Boa prática |
| Conservação a quente                | numérico | °C         | **≥ 65 °C**                                | Código AHRESP    | Boa prática |
| Arrefecimento de confecionados      | numérico | °C / tempo | até **5 °C em ≤ 2 h**                      | Código AHRESP    | Boa prática |
| Refrigeração (geral)                | numérico | °C         | **0–7 °C** (0–4 °C em frio positivo único) | Código AHRESP    | Boa prática |
| Congelados                          | numérico | °C         | **≤ −12 °C**                               | Código AHRESP    | Boa prática |
| Ultracongelados                     | numérico | °C         | **≤ −18 °C**                               | Código AHRESP    | Boa prática |
| Óleo de fritura — temperatura       | numérico | °C         | **≤ 180 °C**                               | Portaria 1135/95 | Lei         |
| Óleo de fritura — compostos polares | numérico | %          | **≤ 25 %**                                 | Portaria 1135/95 | Lei         |

### PCC adicionais para produtos de origem animal (lei — sobrepõe-se ao código)

| Produto                                          | Limite                                        | Fonte         |
| ------------------------------------------------ | --------------------------------------------- | ------------- |
| Carne (peças)                                    | ≤ 7 °C                                        | Reg. 853/2004 |
| Miudezas / vísceras                              | ≤ 3 °C                                        | Reg. 853/2004 |
| Aves de capoeira                                 | ≤ 4 °C                                        | Reg. 853/2004 |
| Carne picada                                     | ≤ 2 °C (ou congelada ≤ −18 °C)                | Reg. 853/2004 |
| Preparados de carne                              | ≤ 4 °C                                        | Reg. 853/2004 |
| Pescado fresco                                   | próximo do gelo fundente (≈ 0 °C)             | Reg. 853/2004 |
| Pescado congelado                                | ≤ −18 °C                                      | Reg. 853/2004 |
| Pescado a tratar contra parasitas (cru/marinado) | ≤ −20 °C durante ≥ 24 h                       | Reg. 853/2004 |
| Leite cru                                        | ≤ 6–8 °C (armazenagem) / ≤ 10 °C (transporte) | Reg. 853/2004 |
| Higienização de utensílios                       | água ≥ 82 °C                                  | Reg. 853/2004 |

---

## 3. Discrepâncias conhecidas (a AI tem de as expor, não esconder)

1. **Cozedura: 65 °C (Código AHRESP) vs 75 °C (Codex / guias internacionais).** Ambos boa prática. O código AHRESP, adotado, dá conformidade a 65 °C; planos baseados no Codex usam 75 °C. Desempate: plano do estabelecimento.
2. **Congelados: −12 °C (Código AHRESP) vs −18 °C (Reg. 853/2004, lei, para origem animal).** A lei prevalece: para produto animal, ≤ −18 °C.

---

## 4. Pré-requisitos (PRP) — verificações booleanas/texto

Lista dos programas de pré-requisitos (AHRESP), cruzada com as áreas que a ASAE fiscaliza:

1. Instalações e equipamentos (estado, separação cru/cozinhado)
2. Limpeza e desinfeção (plano + evidência)
3. Controlo de pragas (contrato + relatórios)
4. Manutenção técnica e calibração de termómetros
5. Contaminação física e química
6. Alergénios e contaminação cruzada
7. Gestão de resíduos
8. Controlo da água (potabilidade)
9. Pessoal — higiene e estado de saúde (fichas de aptidão)
10. Matérias-primas / receção / seleção de fornecedores
11. Controlo de temperaturas (suporta os PCC)
12. Metodologia de trabalho
13. Informação ao consumidor (alergénios, validade)
14. Controlo de prazos de validade
15. Manipulação de alimentos devolvidos
    16/17. Doação de alimentos (opcional, só se aplicável)
    Base legal qualitativa: Reg. (CE) 852/2004 (Anexo II) + Reg. 178/2002.

---

## 5. Critérios de prova que a ASAE valoriza (requisitos de produto, não campos do item)

A maioria das não conformidades vem da **falta de evidência de execução**, não da ausência de plano. O produto tem de garantir:

- Quem + quando + como (primitivo `verificacao` + foto)
- Registos **não retroativos**, com hora autoritária do dispositivo
- Valores **não repetidos automaticamente** (sinal de fraude)
- Mostrar o que **faltou**, não só o feito (instâncias `em_falta`)
- Ações corretivas registadas e autenticadas
- Plano atualizado quando muda menu/equipamento (versionamento de template)

---

## 6. Mapeamento para `checklist_item`

| Campo do controlo | Coluna                                                |
| ----------------- | ----------------------------------------------------- |
| O que monitoriza  | `texto`                                               |
| Tipo              | `tipo_resposta` (numerico/booleano/texto/foto)        |
| Unidade           | `unidade`                                             |
| Limite            | `limite_min` / `limite_max`                           |
| Fonte do limite   | (novo) campo de proveniência — para citação/auditoria |
| Estatuto          | (novo) lei / boa prática / plano                      |
| Frequência        | `frequencia` no `checklist_template`                  |

---

## 7. Corpus do RAG (camadas)

- **Lei:** Portaria 1135/95 (óleo); Reg. 853/2004 (cadeia de frio animal, higienização).
- **Moldura + PRP:** Reg. 852/2004; formações/PPR AHRESP.
- **Boa prática (números de cozedura/conservação):** Código de Boas Práticas AHRESP; manual de boas práticas 2008.
- **Vinculativo por cliente:** plano HACCP do estabelecimento (importado por tenant).
  Regra transversal: citar a fonte; expor divergências; nunca descer abaixo do mínimo legal; nunca inventar.
