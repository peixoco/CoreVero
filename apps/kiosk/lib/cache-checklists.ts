// lib/cache-checklists.ts
// Cache SQLite leve para a lista de templates de checklist devolvida por
// obter_checklists_kiosk(). Padrão análogo a cache-pin.ts.
//
// Objectivo: mostrar a lista mais depressa enquanto a chamada ao servidor
// ainda está em curso (evita ecrã em branco ao abrir a secção).
//
// ATENÇÃO — online-only:
//   A cache NÃO habilita funcionamento offline. Sem rede, a secção de
//   checklists mostra "indisponível sem ligação" e não deixa iniciar
//   preenchimento, independentemente do conteúdo em cache.
//   Os dados em cache servem apenas para rendering rápido quando online.
//
// Throttle: só refrescamos da rede 1x / 5 min (igual a cache-pin).
// TTL da cache: 1 hora — ao expirar a lista fica vazia até nova leitura online.

import * as SQLite from "expo-sqlite";
import type { ChecklistKiosk } from "@corevero/core";

const CHAVE_CACHE = "checklists_v1";
const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hora
const REFRESH_MIN_MS = 5 * 60 * 1000; // 5 minutos

// Partilha a mesma base de dados da cache de PINs (cache.db).
let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;
let ultimoRefresh = 0;

async function getDb(): Promise<SQLite.SQLiteDatabase> {
  if (!dbPromise) {
    dbPromise = (async () => {
      const db = await SQLite.openDatabaseAsync("cache.db");
      await db.execAsync(`
        pragma journal_mode = WAL;
        create table if not exists cache_checklists (
          chave         text primary key not null,
          dados_json    text not null,
          atualizado_em integer not null
        );
      `);
      return db;
    })();
  }
  return dbPromise;
}

/**
 * Guarda os dados de checklists na cache local.
 * Chamado após cada leitura bem-sucedida de obter_checklists_kiosk.
 */
export async function guardarChecklistsCache(
  checklists: ChecklistKiosk[],
): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `insert or replace into cache_checklists (chave, dados_json, atualizado_em)
     values (?, ?, ?)`,
    CHAVE_CACHE,
    JSON.stringify(checklists),
    Date.now(),
  );
  ultimoRefresh = Date.now();
}

/**
 * Lê a lista de checklists em cache (se existir e não expirada).
 * Devolve array vazio quando não há dados ou estão expirados.
 */
export async function obterChecklistsCache(): Promise<ChecklistKiosk[]> {
  const db = await getDb();
  const row = await db.getFirstAsync<{
    dados_json: string;
    atualizado_em: number;
  }>(
    `select dados_json, atualizado_em
       from cache_checklists
      where chave = ?`,
    CHAVE_CACHE,
  );
  if (!row) return [];
  if (Date.now() - row.atualizado_em > CACHE_TTL_MS) return [];
  try {
    return JSON.parse(row.dados_json) as ChecklistKiosk[];
  } catch {
    return [];
  }
}

/**
 * Verifica se o throttle de refresh ainda está activo (< 5 min desde o último).
 * Se true, o chamador pode saltar a chamada ao servidor.
 */
export function checklistsCacheRecente(): boolean {
  return Date.now() - ultimoRefresh < REFRESH_MIN_MS;
}
