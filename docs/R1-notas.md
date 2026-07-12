# R1 — Notas de execução (2026-07-12)

Fecho da Frente A: deteção de discrepância entre a hora do dispositivo e a hora do servidor, sinalização no admin e teste de ponta a ponta do DoD. Executado conforme o doc 09 (v3), com delegação aos subagentes (explorador → executor → revisor-sql) e verificação na BD real (`xghfsudvpsgqkslobttj`).

## O que foi feito

### 1. Descoberta (explorador)
- Coluna de timestamp de servidor: `verificacao.momento_servidor`, exposta em `vista_picagem` (definição vigente em `20260628310000_imutabilidade_correcoes.sql`, `security_invoker=true`, 15 colunas).
- Confirmado que **não existe** tabela de configuração por empresa (só `empresa.retencao_foto_dias`), pelo que o limiar seguiu o caminho previsto: constante em `packages/core`, sem infraestrutura nova (âmbito do R3).

### 2. Migração `20260712160000_desvio_picagem.sql`
- Recria `vista_picagem` com as 15 colunas na mesma ordem + `desvio_segundos = extract(epoch from momento_servidor - momento_dispositivo)::int` como 16.ª coluna (positivo = servidor à frente do dispositivo).
- `security_invoker=true` preservado; grant explícito `select` a `authenticated` reafirmado (invariante 6).
- **Aprovada pelo revisor-sql sem achados** antes do push. Verificação read-only pós-push: a vista remota devolve `desvio_segundos` (integer). Tipos regenerados (`database.types.ts`).
- `LIMIAR_DESVIO_SEGUNDOS = 300` em `packages/core/src/desvio.ts`, com TODO para migrar para configuração por empresa no R3.

### 3. Sinalização no admin
- Badge âmbar «desvio» (paleta de aviso já existente) em `registos/page.tsx` e na vista de dia do colaborador (`colaboradores/[id]/page.tsx`), quando `abs(desvio_segundos) > LIMIAR_DESVIO_SEGUNDOS`.
- Tooltip com o desvio legível na perspetiva do dispositivo (ex.: `−7 min vs servidor`), via helper partilhado `formatarDesvio` em `packages/core`.
- Puramente informativo: não bloqueia nada, não altera estados; a decisão é humana. O kiosk não foi tocado.

### 4. Teste do DoD da Frente A — `tests/09_dod_frente_a_test.sql`
Mês sintético (trabalhador dedicado, timestamps UTC sem ambiguidade) com 7 asserções, todas verdes na suite completa (`tests/run_local.sh`):
- dia com intervalo a atravessar o meio-dia: 8 h trabalho + 1 h pausa descontada, 1 turno;
- dia com dois turnos: 8 h trabalho, 0 pausa, 2 turnos;
- anulação seguida de correção manual: a anulada não conta para horas nem turnos, e `sequencia_valida` volta a aceitar entrada após a anulação;
- desvio injetado de 420 s: `desvio_segundos = 420` nessa picagem e `0` nas restantes.

### 5. Gate de build na raiz (nota do R0 resolvida)
- `package.json` raiz ganhou `"build": "npm run build -w admin && npm run typecheck -w kiosk"`; `apps/kiosk` ganhou `"typecheck": "tsc --noEmit"`.
- Linha do gate no `CLAUDE.md` alinhada. Verificado verde na raiz.

## Divergências (regra de parar e reportar)

1. **Timestamp da migração fora de ordem** — a migração foi inicialmente criada como `20260712090000`, anterior às migrações `20260712150000+` já aplicadas no remoto (R0), o que faria o `supabase db push` recusá-la. Renomeada para `20260712160000` antes do push (conteúdo intacto; a aprovação do revisor-sql manteve-se válida) e a suite local reconfirmada.
2. **Gate `npm run build` inexistente na raiz** — o `CLAUDE.md` documentava um script que não existia (`Missing script: "build"`); durante o R1 o gate correu em `apps/admin`. Resolvido nesta release (ponto 5 acima).
3. **`db push` exigiu aprovação humana** — o classificador de permissões bloqueou a aplicação automática da migração em produção; o push foi feito manualmente pelo fundador. Nota operacional, não defeito.
4. **Regra 7 (paredeParaUTC)** — sem divergências: o teste SQL injeta timestamps UTC diretamente (camada SQL, sem conversão de hora de parede); nenhum código de app novo manipula horas de parede.

## Commits

- `cc27e11` — R1: desvio dispositivo/servidor em vista_picagem
- `98c272e` — R1: sinalização de desvio dispositivo/servidor no admin
- `6bd9847` — R1: teste DoD Frente A (mês sintético, pausas, anuladas, desvio)
- (este commit) — R1: fecho — docs 09 v3.1, R1-notas, gate de build na raiz

## Estado no fecho

Build raiz (admin + kiosk) verde; suite SQL completa verde; migração aplicada e verificada na BD real. Frente A fechada — o R2 (HACCP) passa a release atual.
