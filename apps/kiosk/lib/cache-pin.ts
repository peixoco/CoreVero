// lib/cache-pin.ts
// Autorização offline (Sprint 3b).
//
// O que isto resolve: durante um corte de rede PROLONGADO, a iniciar_picagem
// (que valida o PIN no servidor) não responde. Sem isto, o colaborador não pica.
// Com isto, o kiosk valida o PIN localmente contra uma cache de HMACs e deixa
// picar; a picagem entra na fila como "autorizada offline" e o servidor
// re-valida no drain.
//
// Segurança (modelo assumido, ver doc 07):
//   - A chave HMAC do dispositivo vive no KEYCHAIN (expo-secure-store), nunca
//     num ficheiro em claro. Extrair a cache (SQLite) sem a chave é inútil.
//   - HMAC de PIN de 4 dígitos é fraco (10 000 combinações). NÃO é a segurança.
//     A segurança é o CONJUNTO: chave no Keychain + foto é a prova + revogar kiosk.
//   - O PIN em claro NUNCA viaja nem é guardado. A cache só tem HMACs.
//
// Compatibilidade com o servidor (CRÍTICO): o pgcrypto calcula
//   hmac(codigo || ':' || pin, chave_hex, 'sha256')
// tratando a chave como os BYTES DO TEXTO hex (não os bytes descodificados).
// Por isso aqui a chave entra como utf8ToBytes(chaveHex) — igual byte-a-byte.
//
// Dependências nativas: expo-secure-store (Keychain) -> exige rebuild.
// Dependência JS: @noble/hashes (HMAC-SHA256 puro JS, sem nativo).
//   npx expo install expo-secure-store
//   npm i @noble/hashes@^1.4.0

import * as SQLite from 'expo-sqlite';
import * as SecureStore from 'expo-secure-store';
import * as Crypto from 'expo-crypto';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha256';
import { utf8ToBytes, bytesToHex } from '@noble/hashes/utils';
import { supabase } from './supabase';

const KEY_NAME = 'corevero_device_hmac_key';
const REFRESH_MIN_MS = 5 * 60 * 1000;       // não refrescar a cache mais que 1x/5min
// Validade local da cache. Sem refresh dentro deste prazo, a validação offline
// PÁRA — protege um tablet roubado mantido offline e evita validar contra dados
// muito antigos. Generoso para o piloto (cobre um fim de semana); baixar = mais
// seguro, menos tolerante a cortes longos.
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 dias

let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;
let jaRegistou = false;       // chave registada no servidor nesta sessão
let ultimoRefresh = 0;        // timestamp do último refresh bem-sucedido

async function getDb(): Promise<SQLite.SQLiteDatabase> {
  if (!dbPromise) {
    dbPromise = (async () => {
      const db = await SQLite.openDatabaseAsync('cache.db');
      await db.execAsync(`
        pragma journal_mode = WAL;
        create table if not exists cache_pin (
          codigo_pessoal text primary key not null,
          nome           text not null,
          trabalhador_id text not null,
          pin_hmac       text not null
        );
        create table if not exists cache_meta (
          chave text primary key not null,
          valor text not null
        );
      `);
      return db;
    })();
  }
  return dbPromise;
}

async function marcarRefresh(): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `insert or replace into cache_meta (chave, valor) values ('ultimo_refresh', ?)`,
    String(Date.now()),
  );
}

// Cache expirada = sem refresh dentro do TTL (ou nunca refrescada).
// Sobrevive a reinícios da app porque o timestamp está em SQLite.
export async function cacheExpirada(): Promise<boolean> {
  const db = await getDb();
  const row = await db.getFirstAsync<{ valor: string }>(
    `select valor from cache_meta where chave = 'ultimo_refresh'`,
  );
  if (!row) return true;
  const ts = Number(row.valor);
  if (!Number.isFinite(ts)) return true;
  return Date.now() - ts > CACHE_TTL_MS;
}

// --- Chave do dispositivo (Keychain) -----------------------------------------
// Gera 32 bytes aleatórios na primeira vez e guarda em hex no Keychain.
// A chave NUNCA sai daqui em claro para AsyncStorage nem para a cache.
async function obterOuCriarChave(): Promise<string> {
  const existente = await SecureStore.getItemAsync(KEY_NAME);
  if (existente) return existente;
  const bytes = await Crypto.getRandomBytesAsync(32);
  const hex = bytesToHex(bytes);
  await SecureStore.setItemAsync(KEY_NAME, hex);
  return hex;
}

// HMAC byte-a-byte igual ao servidor (ver nota de compatibilidade no topo).
function calcularHmac(chaveHex: string, codigo: string, pin: string): string {
  return bytesToHex(hmac(sha256, utf8ToBytes(chaveHex), utf8ToBytes(`${codigo}:${pin}`)));
}

// --- Registo da chave no servidor --------------------------------------------
async function registarChave(chaveHex: string): Promise<void> {
  const { error } = await supabase.rpc('registar_chave_kiosk', { p_chave_hex: chaveHex });
  if (error) throw error;
  jaRegistou = true;
}

// --- Refresh da cache (online) -----------------------------------------------
// Substitui a cache inteira: trabalhadores desativados/removidos saem; PINs
// mudados ficam com o HMAC novo. Throttled a 1x/5min, salvo forçado.
export async function refrescarCache(forcar = false): Promise<void> {
  if (!forcar && Date.now() - ultimoRefresh < REFRESH_MIN_MS) return;

  const chave = await obterOuCriarChave();
  if (!jaRegistou) {
    try { await registarChave(chave); } catch { /* tenta na chamada ao RPC abaixo */ }
  }

  let { data, error } = await supabase.rpc('obter_cache_pins');

  // Chave ainda não registada no servidor -> regista e tenta outra vez.
  if (error && /registada/i.test(error.message ?? '')) {
    await registarChave(chave);
    ({ data, error } = await supabase.rpc('obter_cache_pins'));
  }
  if (error) throw error;
  if (!Array.isArray(data)) return;

  const db = await getDb();
  await db.withTransactionAsync(async () => {
    await db.runAsync('delete from cache_pin');
    for (const r of data as any[]) {
      await db.runAsync(
        `insert into cache_pin (codigo_pessoal, nome, trabalhador_id, pin_hmac)
         values (?, ?, ?, ?)`,
        r.codigo_pessoal, r.nome, r.trabalhador_id, r.pin_hmac,
      );
    }
  });
  ultimoRefresh = Date.now();
  await marcarRefresh(); // persiste para o TTL sobreviver a reinícios
}

// --- Validação offline -------------------------------------------------------
// Devolve o trabalhador se o PIN bater com o HMAC em cache; null caso contrário.
export type TrabalhadorOffline = { trabalhador_id: string; nome: string };

export async function validarPinOffline(
  codigo: string, pin: string,
): Promise<TrabalhadorOffline | null> {
  // Cache expirada (sem refresh dentro do TTL) -> não valida offline.
  if (await cacheExpirada()) return null;

  const chave = await SecureStore.getItemAsync(KEY_NAME);
  if (!chave) return null; // sem chave não há como validar offline

  const db = await getDb();
  const row = await db.getFirstAsync<{
    nome: string; trabalhador_id: string; pin_hmac: string;
  }>(`select nome, trabalhador_id, pin_hmac from cache_pin where codigo_pessoal = ?`, codigo);
  if (!row) return null;

  const mac = calcularHmac(chave, codigo, pin);
  if (mac !== row.pin_hmac) return null;
  return { trabalhador_id: row.trabalhador_id, nome: row.nome };
}

// Há cache utilizável? (para a UI saber se a validação offline é sequer possível)
export async function temCache(): Promise<boolean> {
  const db = await getDb();
  const row = await db.getFirstAsync<{ n: number }>(`select count(*) as n from cache_pin`);
  return (row?.n ?? 0) > 0;
}
