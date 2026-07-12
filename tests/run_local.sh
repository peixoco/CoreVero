#!/usr/bin/env bash
# =====================================================================
# run_local.sh — corre a suite de testes SQL num Postgres local
# descartável (initdb num diretório temporário; nada persiste).
#
# Requisitos: Postgres com contrib no PATH (initdb, pg_ctl, psql).
# Uso: tests/run_local.sh   (a partir da raiz do repo)
#
# Limitação conhecida: as migrações de pg_cron e pg_net são SALTADAS
# (extensões só existem no Supabase). Nada nos testes depende delas.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C   # evita "postmaster became multithreaded" no macOS

PORT="${PORT:-54329}"
DIR="$(mktemp -d /tmp/corevero-pg.XXXXXX)"
LOG="$DIR/postgres.log"

cleanup() {
  if [ "${FALHOU_ARRANQUE:-0}" = 1 ] && [ -f "$LOG" ]; then tail -20 "$LOG"; fi
  pg_ctl -D "$DIR" stop -m immediate >/dev/null 2>&1 || true
  rm -rf "$DIR"
}
trap cleanup EXIT

initdb -D "$DIR" -U postgres --auth=trust --no-locale >/dev/null
FALHOU_ARRANQUE=1
pg_ctl -D "$DIR" -o "-p $PORT -k $DIR -c listen_addresses=''" -l "$LOG" start >/dev/null
FALHOU_ARRANQUE=0

PSQL=(psql -h "$DIR" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)

echo "== bootstrap local + stub de storage"
"${PSQL[@]}" -f tests/00_local_bootstrap.sql
"${PSQL[@]}" -f tests/99_storage_stub_local.sql

echo "== migrações"
for m in supabase/migrations/*.sql; do
  case "$m" in
    *20260628260000_limpar_autorizacoes.sql|*20260628340000_retencao_foto.sql)
      echo "   SKIP (pg_cron/pg_net indisponíveis fora do Supabase): $(basename "$m")"
      continue;;
  esac
  "${PSQL[@]}" -f "$m" >/dev/null
done

echo "== seed"
"${PSQL[@]}" -f supabase/seed.sql >/dev/null

echo "== testes"
FALHAS=0
for t in tests/0*_test.sql; do
  echo "-- $(basename "$t")"
  if ! "${PSQL[@]}" -f "$t"; then
    FALHAS=$((FALHAS + 1))
    echo "   FALHOU: $t"
  fi
done

if [ "$FALHAS" -gt 0 ]; then
  echo "SUITE: $FALHAS ficheiro(s) de teste falharam"
  exit 1
fi
echo "SUITE: todos os testes passaram"
