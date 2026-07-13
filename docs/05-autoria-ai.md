# 05 — Autoria assistida por AI (onboarding + RAG híbrido)

> Como a AI ajuda a criar checklists sem nunca ser autoridade sobre um limite crítico.
> Princípio: a AI **rascunha e esclarece; o humano aprova**. Nenhum limite crítico vem da memória do modelo.

---

## 1. Papel da AI

- **Onboarding:** entrevista o restaurante (tipo de cozinha, colaboradores, equipamentos de frio, fritadeira, banho-maria, receção, pragas/água/calibração) e **recomenda quais templates do catálogo ativar e como parametrizá-los** (ex.: 3 frigoríficos + 2 arcas → 5 itens de temperatura).
- **Esclarecimento:** responde a dúvidas ("porque este limite?", "o que diz o código sobre descongelação?") **sempre a partir de uma fonte** do corpus, citando o trecho.
- **NÃO** inventa checklists nem limites. **NÃO** é autoridade final sobre um limite crítico. Gate de aprovação humana antes de qualquer template ir para produção.

---

## 2. A regra de ouro (grounding)

A AI responde apenas a partir de:

1. **um trecho recuperado do corpus** (camada documental), ou
2. **um valor da tabela de limites** (camada determinística).
   Se a resposta não está em nenhuma das duas, diz que não sabe e remete para o plano HACCP do estabelecimento / responsável de segurança alimentar. **Nunca responde da memória do modelo.**

> Acesso aos documentos é necessário mas **não suficiente**: mesmo com o trecho certo recuperado, o modelo pode parafrasear mal um número. Por isso o número que vira um _controlo_ na checklist vem da **tabela**, não do texto livre do modelo. Os documentos servem para esclarecer e justificar; a tabela é a autoridade dos números.

---

## 3. Arquitetura híbrida — três peças

**(A) LLM — conversa e estrutura.**
Conduz a entrevista, seleciona e parametriza templates. Saída em **JSON Schema** (structured outputs). **Nunca emite um limite crítico como texto livre** — propõe a _estrutura_ (que templates, que itens, quantos), deixando os limites por preencher.

**(B) Tabela de limites — autoridade dos números.**
Destilada do doc 04. Cada linha: controlo, tipo, unidade, `limite_min/max`, **fonte**, **estatuto** (lei / boa prática / plano), **âmbito** (geral / origem animal / óleo). A hierarquia _lei > código > plano_ e o "nunca abaixo do mínimo legal" vivem na **consulta**, não na esperança de o modelo se portar bem. É daqui que saem os números que entram nos `checklist_item`.

**(C) Recuperação documental (RAG semântico) — base verídica.**
O corpus indexado (em **pgvector**, no próprio Supabase). Para perguntas qualitativas, esclarecimentos e para _justificar_ uma recomendação citando o trecho exato. Não é fonte de limites críticos — é fonte de explicação.

Fluxo: o LLM conduz; a tabela autoriza os números; a recuperação fundamenta a prosa. Os três convergem no resultado — uma checklist proposta + esclarecimentos — **sempre com aprovação humana**.

---

## 4. Fluxo de onboarding (passo a passo)

1. A AI apresenta-se e faz a **entrevista** (uma mensagem, perguntas em lista).
2. O cliente responde.
3. A AI **seleciona** os templates do catálogo aplicáveis e **parametriza** (nº de equipamentos → nº de itens; desativa o que não se aplica, ex.: óleo sem fritadeira).
4. A AI devolve a **estrutura em JSON** (templates + itens + parametrização) — **sem** limites numéricos.
5. O **sistema** percorre cada item numérico e **anexa o limite a partir da tabela** (com fonte e estatuto). O LLM não toca nos números.
6. O JSON mapeia para `checklist_template` / `checklist_item`.
7. **Gate de aprovação humana** antes de produção.
8. Para dúvidas, a AI recupera o trecho do corpus (pgvector) e **cita**.

---

## 5. O contrato — JSON Schema

O LLM produz **estrutura**, não limites. Esquema de saída (resumo):

```
{
  "templates_ativar": [
    {
      "nome": "Temperaturas de frio",
      "frequencia": "diaria",
      "itens": [
        {
          "texto": "Temperatura do frigorífico 1",
          "tipo_resposta": "numerico",
          "unidade": "°C",
          "limite_min": null,      // preenchido pela TABELA, não pelo LLM
          "limite_max": null,      // idem
          "ambito": "geral"        // pista para a tabela escolher a linha certa
        }
      ]
    }
  ],
  "templates_nao_aplicaveis": ["Óleo de fritura"],
  "perguntas_pendentes": ["Tem vitrina refrigerada de sobremesas?"]
}
```

- `limite_min/max` saem **sempre null** do LLM e são preenchidos pela tabela no passo 5.
- `ambito` (geral / origem_animal / oleo / produto_especifico) permite à tabela escolher a linha de maior estatuto aplicável.
- `perguntas_pendentes`: quando a AI assumiria algo, **pergunta** em vez de assumir.
- **Structured outputs** (Ollama/vLLM) força o JSON ao esquema — sem texto solto.
  Mapeamento: `templates_ativar[]` → `checklist_template`; `itens[]` → `checklist_item`.

---

## 6. A tabela de limites — estrutura e resolução

Tabela de referência (catálogo, não por tenant; o plano do cliente sobrepõe-se por tenant):

| coluna                  | exemplo               |
| ----------------------- | --------------------- |
| controlo                | "Confeção (interior)" |
| tipo_resposta           | numerico              |
| unidade                 | °C                    |
| limite_min / limite_max | 65 / null             |
| fonte                   | "Código AHRESP"       |
| referencia              | secção Confeção       |
| estatuto                | boa_pratica           |
| ambito                  | geral                 |

**Regra de resolução** (dado grandeza + produto):

1. Escolher a linha de **maior estatuto aplicável** ao âmbito (lei > boa prática).
2. **Nunca** devolver valor abaixo do mínimo legal (ex.: congelado de origem animal nunca < −18 °C, mesmo que o código admita −12 °C).
3. Se há **divergência de boa prática** (ex.: cozedura 65 °C AHRESP vs 75 °C Codex), devolver a **adotada (AHRESP)** e marcar que existe alternativa.
4. O **plano do estabelecimento** (por tenant), quando importado, sobrepõe-se como valor operativo — limitado pelo mínimo legal.

---

## 7. Regras de citação e segurança

- Responde só de **trecho recuperado** ou **valor de tabela**.
- **Cita** fonte + estatuto em cada limite.
- **Divergências:** expõe ambas, indica a adotada.
- **Omisso:** "não consta no corpus; a definir no plano HACCP do estabelecimento".
- **Disclaimer (T&C):** "não substitui validação por responsável de segurança alimentar" — protege juridicamente, **não** substitui a tabela + citação. Por isso estas não são opcionais.

---

## 8. Stack e faseamento

**Motor:** Ollama (MVP) → vLLM (escala/concorrência). API compatível-OpenAI + structured outputs.
**Modelo:** texto pequeno (Qwen / Llama / Phi-4-mini) chega para o onboarding (validado no teste Opção A); Mistral Small 4 só se precisar de **visão** (import de documentos do SARA).
**Camada de abstração de provider:** o contrato é o JSON Schema; o modelo/endpoint é configuração — trocar é config, não reescrita.
**Recuperação documental:** **pgvector no Supabase** — corpus e tabela de limites na mesma BD, região UE, sem infra nova. Embeddings com modelo pequeno multilingue (PT).
**Hosting da inferência:** Oracle Always Free A1 (texto) / serverless GPU escala-a-zero (visão/escala).

**Faseamento:**

- **Fase 1 (MVP onboarding):** tabela de limites + LLM (conversa + seleção). Sem embeddings. Onboarding funcional e seguro.
- **Fase 2:** + recuperação documental (pgvector) para esclarecimentos e citação do código — _é o requisito de "a LLM tem sempre uma base verídica"_.
- **Fase 3:** + visão (import SARA/PDF) e escala (vLLM).

---

## 9. Decisões e fios em aberto

- **Fechado:** AHRESP como código por defeito; tabela como autoridade dos números; LLM nunca emite limite crítico; pgvector no Supabase como store.
- **Em aberto:** modelo de embeddings concreto (PT); estratégia de chunking do corpus (preservar a unidade "controlo + limite + fonte"); seed inicial da tabela de limites a partir do doc 04; importação do plano por tenant (sobreposição de limites).
