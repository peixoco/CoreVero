# 01 — Arquitetura da Base de Dados

> Sistema de conformidade HACCP com atribuição autenticada (picagem + monitorização).
> Backend: Supabase (Postgres + Storage + Auth + Edge Functions), alocação UE.

---

## 1. Princípios fundadores

1. **A empresa é a fronteira de isolamento.** Cada cliente do SaaS é uma `empresa`. Nenhum dado atravessa empresas.
2. **`empresa_id` em todas as tabelas.** Desnormalização deliberada: cada policy de RLS é um `empresa_id = empresa_atual()` simples, sem joins de vários níveis. Um join falhado numa policy é uma fuga de dados entre clientes.
3. **`verificacao` é o primitivo de prova partilhado.** Quem + onde + quando + foto. Picagens, conclusões de checklist e ações corretivas referenciam-no, em vez de duplicarem a máquina de autenticação.
4. **A captura é imune à rede.** A hora autoritária é a do momento do toque no dispositivo; a hora de receção no servidor é guardada para auditoria e deteção de discrepâncias.
5. **Os registos HACCP são prova.** Tipados, com limites críticos, ações corretivas obrigatórias e versão de template. Não silenciosamente editáveis após fecho.

---

## 2. Região e infraestrutura

- Projeto Supabase criado em região UE: **Frankfurt (`eu-central-1`)** ou **Irlanda (`eu-west-1`)**.
- Base de dados, Storage (buckets de fotos) e Edge Functions na mesma região UE.
- DPA do Supabase aceite. Confirmar que nenhum serviço auxiliar (logs, analytics) processa fora da UE.

---

## 3. Modelo de dados — tabelas

Notas transversais:

- Todas as chaves primárias são `uuid` (`gen_random_uuid()`).
- Todas as tabelas têm `created_at timestamptz default now()`.
- Todas as tabelas de domínio têm `empresa_id uuid not null` (exceto `empresa`).

### 3.1 Tenancy e organização

**`empresa`** — o tenant.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nome | text | |
| plano | text | referência ao plano Stripe |
| lojas_licenciadas | int | limite de lojas pago |
| colaboradores_licenciados | int | limite de colaboradores ativos pago |

**`loja`**
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| nome | text | |
| ativa | bool | |

**`trabalhador`** — pertence à empresa; pode picar em qualquer loja da empresa.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| nome | text | |
| codigo_pessoal | text | único por empresa |
| ativo | bool | só ativos contam para a licença |

**`trabalhador_loja`** — afetação/escala (opcional, não governa permissão de picagem).
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| trabalhador_id | uuid FK | |
| loja_id | uuid FK | |

### 3.2 Primitivo de verificação

**`verificacao`** — um trabalhador autenticou-se (código + foto) numa loja, a uma hora.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| trabalhador_id | uuid FK | |
| loja_id | uuid FK | onde ocorreu |
| momento_dispositivo | timestamptz | **hora autoritária** (toque) |
| momento_servidor | timestamptz | receção (auditoria/anti-fraude) |
| foto_url | text | bucket UE; retenção curta (ver §6) |

### 3.3 Picagens

**`picagem`**
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| verificacao_id | uuid FK | |
| tipo | text | `entrada` / `saida` |

### 3.4 Checklists HACCP

**`checklist_template`** — vive na empresa; partilhável ou própria de loja.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| loja_id | uuid FK nullable | `null` = template da empresa; preenchido = checklist própria da loja |
| nome | text | |
| frequencia | text | ex. `diaria_2x`, `por_turno` |
| versao | int | incrementa a cada alteração (integridade de auditoria) |
| ativo | bool | |

**`checklist_template_loja`** — atribui um template da empresa a lojas específicas.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| template_id | uuid FK | |
| loja_id | uuid FK | |

**`checklist_item`** — item tipado com limites críticos.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| template_id | uuid FK | |
| ordem | int | |
| texto | text | |
| tipo_resposta | text | `booleano` / `numerico` / `texto` / `foto` |
| unidade | text nullable | ex. `°C` |
| limite_min | numeric nullable | limite crítico inferior |
| limite_max | numeric nullable | limite crítico superior |

**`checklist_instancia`** — um preenchimento concreto.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| template_id | uuid FK | |
| template_versao | int | **snapshot** da versão usada |
| loja_id | uuid FK | |
| verificacao_id | uuid FK | quem fez |
| due_at | timestamptz nullable | quando devia ser feita (frequência) |
| estado | text | `pendente` / `concluida` / `em_falta` |

**`checklist_resposta`**
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| instancia_id | uuid FK | |
| item_id | uuid FK | |
| valor | text | |
| conforme | bool | calculado contra `limite_min/max` |

**`acao_corretiva`** — obrigatória quando `conforme = false`.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| resposta_id | uuid FK | |
| verificacao_id | uuid FK | quem corrigiu (autenticado) |
| descricao | text | o que foi feito |

### 3.5 Notificações

**`notificacao`** — multi-canal, não acoplada ao WhatsApp.
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| empresa_id | uuid FK | |
| origem_id | uuid | ex. `checklist_resposta` não conforme |
| canal | text | `email` (MVP, via Resend) / `in_app` / `whatsapp` (pós-MVP) |
| destinatario | text | configurável por loja |
| estado | text | `pendente` / `enviada` / `falhou` |
| tentativas | int | |

### 3.6 Identidade e acesso

**`utilizador_app`** — admins/gestores (contas reais no Supabase Auth).
| coluna | tipo | notas |
|---|---|---|
| id | uuid PK | = `auth.users.id` |
| empresa_id | uuid FK | injetado no JWT (claim) |
| ambito | text | `empresa` / `loja` |
| loja_id | uuid FK nullable | se âmbito = loja |

> **Os colaboradores que picam NÃO são utilizadores do Auth.** Identificam-se por `codigo_pessoal` + foto num dispositivo partilhado (kiosk) que se autentica como uma identidade de loja. Ver §5.

---

## 4. Isolamento multi-tenant (RLS)

Estratégia: **RLS ativa em todas as tabelas**, policy uniforme baseada no `empresa_id` do JWT.

Função auxiliar:

```sql
create function empresa_atual() returns uuid
language sql stable as $$
  select (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid
$$;
```

Policy-tipo (replicada em cada tabela de domínio):

```sql
alter table picagem enable row level security;

create policy tenant_isolation on picagem
  using (empresa_id = empresa_atual())
  with check (empresa_id = empresa_atual());
```

Regras:

- O claim `empresa_id` é escrito em `app_metadata` (não editável pelo utilizador) no signup/convite do admin.
- Admins com âmbito `loja` recebem uma policy adicional que filtra também por `loja_id`.
- A identidade do kiosk só pode **inserir** `verificacao`/`picagem`/`checklist_*` da sua própria loja — nunca ler dados de gestão.

---

## 5. Licenciamento por lugares (enforcement na BD)

O preço é por **limite** (seats), não por consumo medido. O sistema impede ultrapassar o limite pago.

- `empresa.colaboradores_licenciados` = nº máximo de `trabalhador.ativo = true`.
- `empresa.lojas_licenciadas` = nº máximo de `loja.ativa = true`.
  Enforcement no momento de ativar (trigger `before insert/update`):

```sql
-- pseudo: ao ativar um trabalhador, contar ativos da empresa
-- e rejeitar se contagem > colaboradores_licenciados
```

Desativar não apaga: o histórico de picagens e registos HACCP mantém-se. Desativados não contam para a licença.

> Na fase de teste (sem Stripe), os limites podem ser definidos manualmente ou folgados; a estrutura de contagem e enforcement fica pronta para quando entrar a faturação. A estrutura multi-tenant mantém-se mesmo com um único tenant.

---

## 6. Retenção — o conflito RGPD vs HACCP

Os registos servem dois senhores com prazos opostos:

- **RGPD**: minimizar; a **foto** (dado pessoal) deve ter retenção curta.
- **HACCP**: a **prova de conformidade** deve ser retida por período alargado para inspeção (ASAE).
  Regra de desenho: **separar a prova do registo da foto de atribuição.**
- A `verificacao` mantém `valor`, `conforme`, horas e quem (prova HACCP) — retenção longa.
- O `foto_url` aponta para o bucket; a foto é purgável independentemente, num prazo mais curto.
- Implementar job de expiração de fotos (Edge Function agendada) sem tocar nos registos de conformidade.
  > Prazos concretos a confirmar com jurista de proteção de dados (RGPD) e responsável de segurança alimentar (HACCP). Não são decisão de engenharia.

---

## 7. Integridade de auditoria

- `checklist_instancia.template_versao` congela a versão de template usada — a prova é interpretável mesmo que o template mude depois.
- Respostas e ações corretivas são **append-only** após o fecho da instância (sem UPDATE/DELETE silencioso; correções fazem-se por novo registo, não por edição).
- `momento_servidor` vs `momento_dispositivo`: discrepâncias grandes são sinalizadas (anti-fraude de relógio).
