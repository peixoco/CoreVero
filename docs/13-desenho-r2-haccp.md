# 13 — Desenho do R2 (HACCP): schema, versionamento e motor de conformidade

> Fecha as decisões de desenho da Frente B antes da execução. **Corrige o doc 01 §3.4**, cujo versionamento por inteiro não congelava os itens — falha de auditoria identificada em 2026-07-13. Alimenta-se do doc 04 (controlos e limites) e prepara a fundação da Vera (doc 05). Após confirmação do fundador, este documento decompõe-se nos prompts de execução R2a/R2b/R2c.

---

## 1. Decisões fechadas

| # | Decisão | Escolha |
|---|---|---|
| D1 | Versionamento de templates | Versões imutáveis como entidade (`checklist_template_versao`); itens pertencem à versão; publicar congela por trigger |
| D2 | Proveniência de limites | `limite_fonte`/`limite_referencia` por item + tabela global `limite_legal` com validação no publicar (nunca abaixo do estatutário) |
| D3 | Motor de conformidade | Contrato genérico, avaliação tipada por `tipo_resposta`, autoridade exclusiva no servidor (RPC definer); fecho bloqueado sem ação corretiva |
| D4 | Frequência/agendamento | Estruturada desde o dia 1 (`frequencia_tipo` + `frequencia_config jsonb`); gerador de instâncias é o passo R2c, mas o schema já o suporta |
| D5 | Âmbito offline | Preenchimento no kiosk **online-only** no R2; offline HACCP é extensão posterior, com decisão própria |

---

## 2. Schema `checklist_*` (substitui doc 01 §3.4)

Notas transversais mantidas: PK uuid, `created_at`, `empresa_id` em todas (exceto `limite_legal`, que é global), RLS policy-tipo `empresa_id = empresa_atual()`.

### 2.1 `limite_legal` — tabela de autoridade (GLOBAL, sem empresa_id, sem RLS de tenant; leitura para todos os roles, escrita só por migração)
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| controlo | text | ex. `oleo_fritura_temperatura` |
| descricao | text | |
| norma | text | ex. `Portaria 1135/95` |
| unidade | text | |
| limite_min | numeric nullable | estatutário |
| limite_max | numeric nullable | estatutário |

Seed inicial (das fontes indexadas — validar contra elas na migração de seed): óleo de fritura ≤180 °C e compostos polares ≤25 % (Portaria 1135/95); temperaturas de cadeia de frio do Reg. 853/2004. **Não semear** valores AHRESP como estatutários — são código de boas práticas, entram como default de template, não como piso legal.

**Papel futuro:** é a autoridade numérica da Vera (doc 05) — a Vera cita fontes via RAG, mas qualquer número que apresente vem desta tabela ou do plano do estabelecimento, nunca de memória de modelo.

### 2.2 `checklist_template` — identidade (mutável, sem conteúdo)
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| loja_id | uuid FK nullable | `null` = template de empresa |
| nome | text | |
| ativo | bool | desativar não apaga histórico |

### 2.3 `checklist_template_versao` — o conteúdo versionado
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| template_id | uuid FK | |
| numero | int | sequencial por template; UNIQUE (template_id, numero) |
| estado | text | `rascunho` / `publicada` / `arquivada` |
| frequencia_tipo | text | `diaria` / `por_turno` / `semanal` / `por_evento` |
| frequencia_config | jsonb | ex. `{"vezes_por_dia":2,"janelas":["08:00","16:00"]}`; validada na app e no publicar |
| publicada_em | timestamptz nullable | |

Regras:
- Só existe **um rascunho** por template de cada vez (constraint parcial).
- `publicar_versao(versao_id)` (RPC definer): valida (≥1 item; limites vs `limite_legal`; config de frequência coerente), marca `publicada`, arquiva a publicada anterior.
- **Trigger de imutabilidade**: versões `publicada`/`arquivada` e os seus itens rejeitam UPDATE/DELETE (mesmo padrão da `picagem`). Editar = `criar_rascunho_de(versao_id)` que clona itens para uma versão `rascunho` nova.

### 2.4 `checklist_item` — pertence à VERSÃO
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| versao_id | uuid FK → checklist_template_versao | **não** ao template |
| ordem | int | |
| texto | text | |
| tipo_resposta | text | `numerico` / `booleano` / `texto` / `foto` |
| unidade | text nullable | |
| limite_min | numeric nullable | só numérico |
| limite_max | numeric nullable | só numérico |
| booleano_conforme | bool nullable | default `true`; `false` inverte ("sinais de pragas: sim" = não conforme) |
| obrigatorio | bool | default `true` |
| limite_fonte | text nullable | `lei` / `codigo_boas_praticas` / `plano_estabelecimento` |
| limite_referencia | text nullable | ex. `Portaria 1135/95`, `AHRESP CBP §x` |
| limite_legal_id | uuid FK nullable → limite_legal | se preenchido, o publicar valida: limites do item nunca menos exigentes que o estatutário |

### 2.5 `checklist_instancia`
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| template_id | uuid FK | |
| versao_id | uuid FK | **substitui o `template_versao int`** — congela por referência a conteúdo imutável |
| loja_id | uuid FK | |
| verificacao_id | uuid FK nullable | quem concluiu; null enquanto `pendente`/`em_falta` |
| due_at | timestamptz nullable | null para `por_evento` |
| estado | text | `pendente` / `concluida` / `em_falta` |
| concluida_em | timestamptz nullable | |

Origem das instâncias: geradas pelo agendador (R2c) para frequências temporais; criadas on-demand no kiosk para `por_evento` (ex. receção de mercadorias).

### 2.6 `checklist_resposta`
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| instancia_id | uuid FK | |
| item_id | uuid FK | item imutável → resposta eternamente interpretável |
| valor | text | representação canónica por tipo |
| foto_url | text nullable | para `tipo_resposta='foto'`; retenção própria (relógio HACCP, não o da foto de atribuição) |
| conforme | bool | **escrito exclusivamente pela RPC do servidor** |

UNIQUE (instancia_id, item_id). Append-only após fecho da instância (trigger).

### 2.7 `acao_corretiva`
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| resposta_id | uuid FK | |
| verificacao_id | uuid FK | quem corrigiu, autenticado |
| descricao | text | |

### 2.8 `notificacao` — mantém-se como no doc 01 §3.5 (email/Resend no MVP). Nota jurídica pendente do doc 12: região/DPA da Resend por confirmar antes de cliente externo.

---

## 3. Motor de conformidade (D3) — contrato

```
avaliar_conformidade(item, valor) → (conforme bool, motivo text)
  numerico : parse(valor); NULL/não-numérico → não conforme ("valor ilegível");
             conforme ⇔ (limite_min is null or v ≥ limite_min) and (limite_max is null or v ≤ limite_max)
  booleano : conforme ⇔ (valor::bool = booleano_conforme)
  texto    : conforme ⇔ obrigatorio → valor não vazio; senão sempre conforme
  foto     : conforme ⇔ foto_url presente
```

Autoridade e fluxo:
1. **Kiosk (UX apenas):** avalia localmente para forçar o fluxo de ação corretiva antes do submit; nunca envia `conforme`.
2. **`registar_respostas_checklist` (RPC SECURITY DEFINER, atómica):** valida a instância (estado, loja do kiosk, versão publicada), reavalia cada resposta com `avaliar_conformidade`, escreve respostas + `conforme`, cria a `verificacao` da conclusão.
3. **Fecho:** a instância só passa a `concluida` se todos os itens `obrigatorio` têm resposta **e** toda a resposta não conforme tem `acao_corretiva`. A RPC recebe as ações corretivas no mesmo payload (o kiosk força a descrição no momento) — sem estado intermédio "concluída com pendências".
4. **Não conformidade ⇒ notificação:** inserção em `notificacao` na mesma transação; envio assíncrono (worker/Edge Function) fora dela.

---

## 4. O que o construtor de templates tem de fazer (R2a, admin)

1. CRUD de templates (identidade) + rascunhos de versão com itens (ordenar, tipos, limites, proveniência).
2. Ligar item a `limite_legal` com pré-preenchimento dos limites estatutários; aviso visual quando o valor do plano é mais exigente (ok) e **bloqueio no publicar** quando é menos exigente.
3. Publicar com o relatório de validação; histórico de versões consultável; "criar rascunho a partir de".
4. Biblioteca de arranque: os 7 templates do doc 04 §4 como **seeds de rascunho** que o admin ajusta e publica — nunca publicados automaticamente (os limites são responsabilidade do plano do estabelecimento).

---

## 5. Faseamento de execução

| Fase | Conteúdo | Gate |
|---|---|---|
| **R2a** | Migrações (2.1–2.7 + triggers + RPCs de versão) + construtor de templates no admin + seeds | Publicar um template real de temperaturas sem tocar em código |
| **R2b** | RPC de preenchimento + motor + fluxo kiosk (online-only) + ação corretiva forçada | Valor fora do limite obriga a corretiva e fica provado quem/quando/onde |
| **R2c** | Agendador (instâncias por frequência + transição para `em_falta`) + notificações Resend + relatório do dia no admin | O relatório mostra o que faltou; a não conformidade chega por email |
| **R2d** | Vera + RAG (doc 05), sobre motor estável, com `limite_legal` como autoridade numérica | Vera responde só com citação; números só da tabela/plano |

Cada fase = uma branch (`r2a/...`), gates verdes, push da branch, PR humano — ciclo do CLAUDE.md.

---

## 6. Fora de âmbito do R2 (explícito)

- Offline de checklists (D5) — extensão futura com decisão própria.
- Edição de instâncias concluídas — não existe; correção é nova instância ou ação corretiva.
- WhatsApp como canal — pós-MVP (doc 01 §3.5).
- Qualquer coisa do doc 10 (visão).
