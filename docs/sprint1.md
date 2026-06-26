# Sprint 1 (parcial) — Identidade e acesso

Camada de **identidade por tipo (admin/kiosk) + RLS diferenciada**, validada contra
Postgres real. Constrói sobre o Sprint 0.

## Ficheiros
- `supabase/migrations/20260626100000_identidade_acesso.sql` — helpers de identidade,
  policy de admin-empresa, RLS do kiosk (insert-only + leitura fina).
- `tests/02_kiosk_admin_test.sql` — 7 testes (admin vê o seu; kiosk insere só a sua loja;
  kiosk não lê gestão/histórico; não insere noutra loja/empresa; não atualiza/apaga).
- `tests/01_isolation_test.sql` — **versão atualizada** do teste do Sprint 0 (os claims
  passam a incluir `tipo:"admin"`, exigido pelas novas policies).

## O que muda
A policy uniforme do Sprint 0 (qualquer `authenticated` via toda a empresa) é substituída por:
- **admin-empresa** — acesso total à sua empresa (`is_admin() and empresa_id = empresa_atual()`).
- **kiosk** — só INSERE eventos da sua loja (`verificacao`, `picagem`, `checklist_*`) e
  LÊ só a fatia fina (a sua loja, trabalhadores ativos, templates/itens ativos). Não lê
  gestão nem histórico; não atualiza nem apaga.

**Modelo de claim (app_metadata):**
```
admin-empresa: { empresa_id, tipo:"admin", loja_id:null }
kiosk:         { empresa_id, tipo:"kiosk", loja_id:"<uuid>" }
```

## Achados de design (importantes)
- **O kiosk gera os uuid no cliente.** Como não tem SELECT nas event tables, `INSERT ... RETURNING`
  é barrado pela RLS. O padrão outbox (offline-first) já minta ids localmente — encaixa.
- **admin-loja ADIADO** de propósito (precisa de denormalizar `loja_id` para
  picagem/resposta/acao; sem caso multi-loja real, evita-se adivinhar a semântica).
- **Gap de baixa severidade** documentado: dentro da MESMA empresa, um kiosk poderia anexar
  um filho (picagem/resposta) ao pai de outra loja. Fecha-se com `loja_id` denormalizado
  quando houver kiosks de várias lojas em simultâneo.

## Aplicar no Supabase (Paris)
1. Copia a migração para `supabase/migrations/` do repo (já tem timestamp, fica depois das 0900/0901).
2. `npx supabase db push` — aplica a nova migração.
3. Os testes correm via `psql "<string Session>" -f tests/02_kiosk_admin_test.sql`.

> **Onboarding do 1.º admin:** depois desta migração, um admin só vê dados se o JWT tiver
> `tipo:"admin"` + `empresa_id` em `app_metadata`. Ao criar o utilizador admin (Auth),
> define `app_metadata = {"empresa_id":"<id>","tipo":"admin","loja_id":null}`. Sem isto,
> o admin entra mas não vê nada (fail-closed) — é o esperado, não um bug.
