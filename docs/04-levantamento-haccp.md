# 04 — Levantamento de Controlos HACCP (Restaurante)

> Inventário dos controlos que um restaurante deve monitorizar, estruturado para mapear em `checklist_template` (grupo) + `checklist_item` (linha).
> **Os valores são indicativos típicos para Portugal.** Os limites e frequências definitivos vêm do plano HACCP da empresa (SARA) / de um responsável de segurança alimentar. Este documento é um superset — cada restaurante ativa só o que se aplica (ex. sem fritadeira → sem controlo de óleo).

---

## 1. Enquadramento

- Base legal: **Regulamento (CE) 852/2004** (higiene dos géneros alimentícios) e Reg. 178/2002. Fiscalização: **ASAE**.
- Dois níveis de controlo:
  - **Pré-requisitos (PRP)** — programas de base (higiene, limpeza, pragas, receção, etc.). A maioria são verificações de tipo booleano/observação.
  - **Pontos Críticos de Controlo (PCC)** — etapas onde um limite crítico mensurável tem de ser cumprido (temperaturas de confeção, conservação, óleo). São tipicamente numéricos com **ação corretiva obrigatória** quando fora do limite.

### Como cada controlo mapeia no produto

| Campo do controlo   | Coluna em `checklist_item`                                   |
| ------------------- | ------------------------------------------------------------ |
| O que se monitoriza | `texto`                                                      |
| Tipo de medição     | `tipo_resposta` (`numerico` / `booleano` / `texto` / `foto`) |
| Unidade             | `unidade`                                                    |
| Limite crítico      | `limite_min` / `limite_max`                                  |
| Frequência          | `frequencia` no `checklist_template`                         |

Os controlos numéricos com limite são os que disparam **conformidade automática + ação corretiva** (e a notificação por email).

---

## 2. Pontos Críticos de Controlo (PCC) — numéricos, com ação corretiva

| Controlo                               | Monitoriza                              | Tipo     | Unidade  | Limite indicativo                                          | Frequência indicativa        |
| -------------------------------------- | --------------------------------------- | -------- | -------- | ---------------------------------------------------------- | ---------------------------- |
| Confeção (cozedura)                    | Temperatura no núcleo do alimento       | numérico | °C       | **≥ 75 °C** no centro                                      | Por confeção / lote          |
| Reaquecimento                          | Temperatura no núcleo                   | numérico | °C       | **≥ 75 °C**, uma única vez                                 | Por reaquecimento            |
| Conservação a quente                   | Temperatura de manutenção               | numérico | °C       | **≥ 65 °C** (UE geral ≥ 63 °C)                             | Durante o serviço (ex. 2/2h) |
| Conservação a frio / refrigeração      | Temperatura da câmara/equipamento       | numérico | °C       | **0–5 °C** (≤ 5 °C; alguns produtos mais baixo)            | 1–2× por dia                 |
| Congelação / conservação de congelados | Temperatura do congelador               | numérico | °C       | **≤ −18 °C**                                               | 1–2× por dia                 |
| Arrefecimento rápido                   | Tempo/temperatura de descida            | numérico | °C / min | Reduzir núcleo rapidamente (ex. > 63 °C → ≤ 10 °C em ≤ 2h) | Por lote arrefecido          |
| Descongelação                          | Em refrigeração, temperatura controlada | numérico | °C       | ≤ 5 °C (nunca à temperatura ambiente)                      | Por descongelação            |
| Óleo de fritura — temperatura          | Temperatura do banho                    | numérico | °C       | **≤ 180 °C** (Portaria 1135/95)                            | Em uso                       |
| Óleo de fritura — degradação           | Compostos polares totais (TPM)          | numérico | %        | **≤ 25 %** (Portaria 1135/95)                              | Diária / por uso             |

> Notas de origem: confeção/reaquecimento ≥75 °C e conservação a quente ≥65 °C constam dos códigos de boas práticas portugueses (AHRESP/DGAV); UE geral cita ≥63 °C para hot holding. Óleo: Portaria 1135/95 (≤180 °C e ≤25 % compostos polares). Refrigeração 0–5 °C e congelados −18 °C: ASAE / códigos de boas práticas. **Confirmar todos com o plano SARA.**

---

## 3. Pré-requisitos (PRP) — verificações e registos

### 3.1 Receção de mercadorias (por entrega)

| Controlo                                        | Tipo          | Limite/critério indicativo |
| ----------------------------------------------- | ------------- | -------------------------- |
| Temperatura de produtos refrigerados na entrega | numérico (°C) | ≤ 5 °C (conforme produto)  |
| Temperatura de produtos congelados na entrega   | numérico (°C) | ≤ −18 °C                   |
| Integridade da embalagem                        | booleano      | Sem danos                  |
| Prazo de validade                               | booleano      | Dentro da validade         |
| Fornecedor aprovado / documentação              | booleano      | Sim                        |
| Higiene do veículo de transporte                | booleano      | Conforme                   |

### 3.2 Armazenamento

| Controlo                                            | Tipo          | Critério indicativo             |
| --------------------------------------------------- | ------------- | ------------------------------- |
| Temperatura de câmaras/equipamentos de frio         | numérico (°C) | Ver PCC refrigeração/congelação |
| Armazém seco — temperatura/humidade                 | numérico      | Ambiente fresco e seco          |
| Rotação de stock (FIFO/FEFO)                        | booleano      | Cumprido                        |
| Separação cru/cozinhado e alergénios                | booleano      | Sem contaminação cruzada        |
| Produtos afastados do solo/paredes (~20 cm)         | booleano      | Cumprido                        |
| Identificação/data de produtos abertos e congelados | booleano      | Etiquetado                      |

### 3.3 Higiene e saúde dos manipuladores

| Controlo                                    | Tipo     | Critério |
| ------------------------------------------- | -------- | -------- |
| Lavagem de mãos nos momentos-chave          | booleano | Cumprido |
| Fardamento limpo e adequado                 | booleano | Conforme |
| Estado de saúde / declaração (sem sintomas) | booleano | Apto     |
| Uso correto de luvas                        | booleano | Conforme |
| Feridas protegidas                          | booleano | Conforme |

### 3.4 Higienização (plano de limpeza)

| Controlo                                      | Tipo              | Critério                   |
| --------------------------------------------- | ----------------- | -------------------------- |
| Limpeza de superfícies de trabalho            | booleano          | Conforme plano (por turno) |
| Limpeza de equipamentos                       | booleano          | Conforme plano             |
| Limpeza de instalações (chão, casas de banho) | booleano          | Conforme plano             |
| Concentração/uso correto de desinfetantes     | booleano/numérico | Conforme ficha técnica     |
| Higienização de termómetros entre amostras    | booleano          | Cumprido                   |

### 3.5 Outros pré-requisitos

| Programa                | Controlo                                          | Tipo              | Frequência indicativa       |
| ----------------------- | ------------------------------------------------- | ----------------- | --------------------------- |
| Controlo de pragas      | Sinais de pragas; visita de empresa especializada | booleano/texto    | Contínuo + visita periódica |
| Controlo da água        | Potabilidade (rede ou análises)                   | booleano/numérico | Conforme plano              |
| Resíduos e óleos usados | Recolha por operador licenciado                   | booleano          | Conforme recolha            |
| Rastreabilidade         | Registo de lotes/fornecedores                     | texto             | Por receção/produção        |
| Alergénios              | Informação e separação                            | booleano          | Contínuo                    |
| Manutenção e calibração | Calibração de termómetros; avarias de equipamento | numérico/texto    | Periódica / por avaria      |
| Formação                | Formação de manipuladores atualizada              | booleano          | Periódica                   |

---

## 4. Tradução para templates (sugestão de arranque)

Templates iniciais recomendados (cada um com a sua frequência):

1. **Temperaturas de frio — diário** (refrigeradores + congeladores) → itens numéricos com limite.
2. **Confeção e serviço** → núcleo de cozedura, conservação a quente → numéricos com limite.
3. **Óleo de fritura** (só se aplicável) → temperatura + compostos polares → numéricos com limite.
4. **Receção de mercadorias** → por entrega → mistura de numérico + booleano.
5. **Higienização** → por turno → booleanos conforme plano.
6. **Higiene pessoal / abertura** → diário → booleanos.
7. **Pré-requisitos periódicos** → pragas, água, calibração, formação → booleano/texto.

Regra de desenho que isto confirma: **nada disto é código.** São templates e itens que o administrador cria e ajusta na UI, com os limites do plano SARA. Um restaurante sem fritadeira desativa o template 3; uma cadeia com plano próprio ajusta limites — sem alterações de software.

---

## 5. Avisos

- Valores indicativos. Os limites críticos, frequências e a própria lista de PCC dependem da **análise de perigos** específica do estabelecimento — input do plano HACCP (SARA) / responsável de segurança alimentar.
- O software regista e prova; não substitui o estudo HACCP.
- Alguns produtos têm temperaturas específicas mais estritas (ex. pescado fresco, lacticínios) — refletir no item, não numa regra global.
