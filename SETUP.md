# SETUP — levar o Sprint 0 para um Supabase real (do zero)

Segue por ordem. Cada passo só depende do anterior.

---

## 0. O que vais ter no fim
- Projeto Supabase em região UE, com o esquema, a RLS e o seed aplicados.
- Um repositório git com as migrações como fonte de verdade.
- (Opcional) o teste de isolamento corrido contra a instância real.

---

## 1. Criar o projeto Supabase (no dashboard — é o entregável "projeto UE" do Sprint 0)
1. https://supabase.com → **New project**.
2. **Region:** escolhe UE — **Frankfurt (eu-central-1)** ou **Ireland (eu-west-1)**.
   Ambas servem; Frankfurt é a escolha comum. (Decisão final tua; doc 02 deixava-a em aberto.)
3. Define uma **database password** forte e guarda-a (vais precisar dela para o seed).
4. Anota o **Project Ref** (Settings → General → Reference ID).
5. **DPA / RGPD:** revê e aceita o DPA do Supabase (Organização → Legal/Compliance).
   Confirma também que nenhum serviço auxiliar (logs/analytics) processa fora da UE.

> Sem este passo não há onde aplicar nada. É um pré-requisito, não código.

---

## 2. Repositório + Supabase CLI
Precisas de Node.js (já tens, por causa do Expo/Next).

```bash
mkdir haccp-saas && cd haccp-saas
git init
npm init -y
npm install supabase --save-dev      # CLI como dependência do projeto (melhor que global)
npx supabase init                    # cria a pasta supabase/
```

> Docker **não** é preciso para aplicar a um projeto remoto. Só é preciso se mais
> tarde quiseres correr o stack local (`npx supabase start`). Para o Sprint 0, salta.

---

## 3. Colocar as migrações e o seed
Copia os ficheiros desta entrega para a estrutura criada pelo `init`:

```
supabase/
  migrations/
    20260625090000_schema.sql
    20260625090100_rls.sql
  seed.sql
```

> **NÃO** copies `tests/00_local_bootstrap.sql` para `supabase/`. Esse cria roles e
> `auth.users` que **já existem** no Supabase — só serve para testar num Postgres local.

---

## 4. Ligar o repo ao projeto e aplicar
```bash
npx supabase login                          # abre o browser, autentica
npx supabase link --project-ref <TEU_REF>   # liga este repo ao projeto remoto
npx supabase db push                         # aplica as migrações 0900/0901 ao remoto
```

`db push` aplica o **esquema + RLS**. Não corre o seed (é de propósito).

---

## 5. Seed (dados do restaurante + tenant B de isolamento)
`db push` não corre `seed.sql`. Corre-o tu, uma vez, contra o remoto:

1. No dashboard: botão **Connect** → modo **Session** → copia a connection string (URI).
2. ```bash
   psql "<CONNECTION_STRING_SESSION>" -f supabase/seed.sql
   ```
   (Usa a string **Session**, não a Transaction/pooler — o seed e o teste precisam
   de sessão.)

> Alternativa destrutiva: `npx supabase db reset --linked` repõe o remoto e corre o
> seed automaticamente. Só num projeto vazio — apaga tudo. Para já, o `psql -f` é mais seguro.

---

## 6. (Opcional) Teste de isolamento contra o remoto
A lógica já está provada localmente (5/5 testes). Para fazer um smoke test na instância real:

```bash
psql "<CONNECTION_STRING_SESSION>" -f tests/01_isolation_test.sql
```

Notas:
- Usa a connection string **Session** (o teste faz `set role` / `set` ao nível da sessão;
  o pooler em modo transação não preserva isso).
- O teste insere 2 linhas descartáveis em `auth.users` (admins de teste). Podes apagá-las
  depois. Se preferires não tocar em `auth.users`, salta este passo — o DoD do Sprint 0
  já está cumprido pela validação local.

---

## 7. Commit
```bash
printf "node_modules/\n.env\n.branches/\n.temp/\n" >> .gitignore
git add supabase tests SETUP.md
git commit -m "Sprint 0: esquema + RLS + seed (multi-tenant, isolamento validado)"
```

Nunca commites a password da BD nem ficheiros `.env`.

---

## Resumo do que cada migração faz
- **20260625090000_schema.sql** — todas as tabelas (doc 01), `empresa_id` em todas,
  FKs compostas `(empresa_id, id)` na cadeia de prova, CHECKs.
- **20260625090100_rls.sql** — `empresa_atual()` + RLS ativa em 14/14 tabelas + policy-tipo
  `empresa_id = empresa_atual()` + grants a `authenticated`.
- **seed.sql** — Empresa A (restaurante) + Empresa B (só para provar isolamento).
