// lib/outbox.ts
// Fila local persistente de picagens (Sprint 3a + 3b).
//
// 3a — itens ONLINE: a iniciar_picagem emitiu um bilhete (autorizacao_id) antes
//      de a câmara abrir; a fila guarda o bilhete e drena via registar_picagem.
//
// 3b — itens OFFLINE: não houve servidor para emitir bilhete. O kiosk validou o
//      PIN localmente (HMAC contra a cache) e afirma o trabalhador_id. A fila
//      guarda trabalhador_id e drena via registar_picagem_offline, que RE-VALIDA
//      o trabalhador no servidor.
//
// Idempotência: o id do item É a chave de idempotência. Reenviar não duplica.
//
// Recusa terminal: se o servidor rejeita a picagem em definitivo (cache obsoleta
// -> trabalhador desativado; bilhete usado/expirado), o item passa a 'recusado'
// e DEIXA de ser tentado — mas NÃO é apagado: fica visível (contarRecusados) para
// o gestor agir. Uma picagem nunca é silenciosamente perdida (doc 07 §1).
//
// Foto: base64 na própria linha; sai com a linha ao concluir. Sem ficheiros órfãos.
//
// Dependência nativa: expo-sqlite (exige rebuild).

import * as SQLite from 'expo-sqlite';
import { decode } from 'base64-arraybuffer';
import { supabase } from './supabase';

export type EstadoItem = 'pendente' | 'registado' | 'recusado';
export type Origem = 'online' | 'offline';

type Linha = {
  id: string;
  origem: Origem;
  autorizacao_id: string;   // '' se offline
  trabalhador_id: string;   // '' se online
  codigo_pessoal: string;   // para reportar recusas; '' se online
  tipo: string;
  momento: string;
  foto_b64: string;
  estado: EstadoItem;
  verificacao_id: string | null;
  foto_path: string | null;
  tentativas: number;
  erro: string | null;
  reportada: number;        // 1 quando a recusa já foi reportada ao servidor
  criado_em: string;
};

let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;

async function temColuna(db: SQLite.SQLiteDatabase, nome: string): Promise<boolean> {
  const cols = await db.getAllAsync<{ name: string }>(`pragma table_info(outbox_item)`);
  return cols.some((c) => c.name === nome);
}

async function getDb(): Promise<SQLite.SQLiteDatabase> {
  if (!dbPromise) {
    dbPromise = (async () => {
      const db = await SQLite.openDatabaseAsync('outbox.db');
      await db.execAsync(`
        pragma journal_mode = WAL;
        create table if not exists outbox_item (
          id             text primary key not null,
          autorizacao_id text not null,
          tipo           text not null,
          momento        text not null,
          foto_b64       text not null,
          estado         text not null default 'pendente',
          verificacao_id text,
          foto_path      text,
          tentativas     integer not null default 0,
          erro           text,
          criado_em      text not null
        );
      `);
      // Migração 3b: colunas novas em bases já existentes (3a).
      if (!(await temColuna(db, 'origem'))) {
        await db.execAsync(`alter table outbox_item add column origem text not null default 'online'`);
      }
      if (!(await temColuna(db, 'trabalhador_id'))) {
        await db.execAsync(`alter table outbox_item add column trabalhador_id text not null default ''`);
      }
      // 3b#1: codigo do trabalhador (para reportar recusas) + flag de report feito.
      if (!(await temColuna(db, 'codigo_pessoal'))) {
        await db.execAsync(`alter table outbox_item add column codigo_pessoal text not null default ''`);
      }
      if (!(await temColuna(db, 'reportada'))) {
        await db.execAsync(`alter table outbox_item add column reportada integer not null default 0`);
      }
      return db;
    })();
  }
  return dbPromise;
}

// Enfileira uma picagem ONLINE (com bilhete).
export async function enfileirarOnline(item: {
  id: string;
  autorizacao_id: string;
  tipo: string;
  momento: string;
  foto_b64: string;
}): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `insert or ignore into outbox_item
       (id, origem, autorizacao_id, trabalhador_id, tipo, momento, foto_b64,
        estado, tentativas, criado_em)
     values (?, 'online', ?, '', ?, ?, ?, 'pendente', 0, ?)`,
    item.id, item.autorizacao_id, item.tipo, item.momento, item.foto_b64,
    new Date().toISOString(),
  );
}

// Enfileira uma picagem OFFLINE (validada localmente; sem bilhete).
export async function enfileirarOffline(item: {
  id: string;
  trabalhador_id: string;
  codigo_pessoal: string;
  tipo: string;
  momento: string;
  foto_b64: string;
}): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `insert or ignore into outbox_item
       (id, origem, autorizacao_id, trabalhador_id, codigo_pessoal, tipo, momento, foto_b64,
        estado, tentativas, reportada, criado_em)
     values (?, 'offline', '', ?, ?, ?, ?, ?, 'pendente', 0, 0, ?)`,
    item.id, item.trabalhador_id, item.codigo_pessoal, item.tipo, item.momento, item.foto_b64,
    new Date().toISOString(),
  );
}

// Pendentes = por enviar (não conta recusadas).
export async function contarPendentes(): Promise<number> {
  const db = await getDb();
  const row = await db.getFirstAsync<{ n: number }>(
    `select count(*) as n from outbox_item where estado != 'recusado'`,
  );
  return row?.n ?? 0;
}

// Recusadas = rejeitadas em definitivo pelo servidor (precisam de atenção humana).
export async function contarRecusados(): Promise<number> {
  const db = await getDb();
  const row = await db.getFirstAsync<{ n: number }>(
    `select count(*) as n from outbox_item where estado = 'recusado'`,
  );
  return row?.n ?? 0;
}

async function porDrenar(): Promise<Linha[]> {
  const db = await getDb();
  return db.getAllAsync<Linha>(
    `select * from outbox_item where estado != 'recusado' order by criado_em asc`,
  );
}

function eDuplicadoStorage(err: any): boolean {
  const msg = String(err?.message ?? '').toLowerCase();
  return msg.includes('exists') || err?.statusCode === '409' || err?.status === 409;
}

// Recusa terminal: o servidor rejeitou a picagem em definitivo. Repetir não muda
// nada (cache obsoleta, bilhete usado/expirado). SQLSTATE 28000 ou mensagem.
function eRecusaTerminal(err: any): boolean {
  if (err?.code === '28000') return true;
  return /inválido|invalido|desativad|utilizada|expirada/i.test(String(err?.message ?? ''));
}

let aDrenar = false;

export async function drenar(): Promise<void> {
  if (aDrenar) return;
  aDrenar = true;
  try {
    const db = await getDb();
    const itens = await porDrenar();

    for (const it of itens) {
      try {
        let fotoPath = it.foto_path;

        // PASSO 1 — registar (idempotente pela chave = it.id)
        if (it.estado === 'pendente') {
          const resp = it.origem === 'offline'
            ? await supabase.rpc('registar_picagem_offline', {
                p_trabalhador_id: it.trabalhador_id,
                p_tipo: it.tipo,
                p_momento_dispositivo: it.momento,
                p_chave_idempotencia: it.id,
              })
            : await supabase.rpc('registar_picagem', {
                p_autorizacao_id: it.autorizacao_id,
                p_tipo: it.tipo,
                p_momento_dispositivo: it.momento,
                p_chave_idempotencia: it.id,
              });

          const { data, error } = resp;

          if (error) {
            if (eRecusaTerminal(error)) {
              // não voltar a tentar; manter visível para o gestor.
              // Apaga a foto (rosto): o report da recusa não precisa dela e não
              // se deve reter um rosto em repouso indefinidamente (minimização).
              await db.runAsync(
                `update outbox_item set estado='recusado', erro=?, foto_b64='' where id=?`,
                error.message, it.id,
              );
            } else {
              // transitório (rede, kiosk revogado à espera de reativação)
              await db.runAsync(
                `update outbox_item set tentativas = tentativas + 1, erro = ? where id = ?`,
                error.message, it.id,
              );
            }
            continue;
          }
          if (!data?.foto_path) {
            await db.runAsync(
              `update outbox_item set tentativas = tentativas + 1, erro = ? where id = ?`,
              'registo sem caminho', it.id,
            );
            continue;
          }

          fotoPath = data.foto_path as string;
          await db.runAsync(
            `update outbox_item
               set estado='registado', verificacao_id=?, foto_path=?, erro=null
             where id=?`,
            (data.verificacao_id as string) ?? null, fotoPath, it.id,
          );
        }

        // PASSO 2 — upload da foto
        if (fotoPath) {
          const { error: upErr } = await supabase.storage
            .from('picagens')
            .upload(fotoPath, decode(it.foto_b64), {
              contentType: 'image/jpeg', upsert: false,
            });

          if (upErr && !eDuplicadoStorage(upErr)) {
            await db.runAsync(
              `update outbox_item set tentativas = tentativas + 1, erro = ? where id = ?`,
              upErr.message, it.id,
            );
            continue;
          }

          await db.runAsync(`delete from outbox_item where id = ?`, it.id);
        }
      } catch (e: any) {
        const db2 = await getDb();
        await db2.runAsync(
          `update outbox_item set tentativas = tentativas + 1, erro = ? where id = ?`,
          String(e?.message ?? e), it.id,
        );
      }
    }

    // PASSO 3 — reportar recusas offline ao servidor (para o admin as ver).
    // Tentado até passar (reportada=0); não engole se a rede falhar agora.
    await reportarRecusas(db);
  } finally {
    aDrenar = false;
  }
}

async function reportarRecusas(db: SQLite.SQLiteDatabase): Promise<void> {
  const recusas = await db.getAllAsync<Linha>(
    `select * from outbox_item
      where estado='recusado' and origem='offline' and reportada=0`,
  );
  for (const r of recusas) {
    const { error } = await supabase.rpc('reportar_picagem_recusada', {
      p_trabalhador_id: r.trabalhador_id || null,
      p_codigo_pessoal: r.codigo_pessoal || null,
      p_tipo: r.tipo,
      p_momento_dispositivo: r.momento,
      p_chave_idempotencia: r.id,
      p_motivo: r.erro ?? 'recusada no drain',
    });
    if (!error) {
      await db.runAsync(`update outbox_item set reportada=1 where id=?`, r.id);
    }
    // se falhar (rede), fica reportada=0 e tenta no próximo drain
  }
}
