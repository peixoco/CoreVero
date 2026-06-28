// lib/outbox.ts
// Fila local persistente de picagens (Sprint 3a, Opção 1).
//
// O QUE entra na fila: registo + upload. O bilhete (autorizacao_id) é emitido
// ONLINE pela iniciar_picagem antes de a câmara abrir; a fila só absorve o que
// vem depois. Por isso a fila NÃO guarda PIN — guarda o bilhete.
//
// Idempotência: o id do item da fila É a chave de idempotência. Por mais vezes
// que um item seja reenviado, registar_picagem só cria a picagem uma vez.
//
// Foto: guardada em base64 NA própria linha. Quando o item drena com sucesso,
// a linha é apagada e os bytes saem com ela. Sem ficheiros órfãos, sem
// expo-file-system.
//
// Dependência nativa: expo-sqlite (exige rebuild do dev client).

import * as SQLite from 'expo-sqlite';
import { decode } from 'base64-arraybuffer';
import { supabase } from './supabase';

export type EstadoItem = 'pendente' | 'registado';

type Linha = {
  id: string;
  autorizacao_id: string;
  tipo: string;
  momento: string;
  foto_b64: string;
  estado: EstadoItem;
  verificacao_id: string | null;
  foto_path: string | null;
  tentativas: number;
  erro: string | null;
  criado_em: string;
};

let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;

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
      return db;
    })();
  }
  return dbPromise;
}

// Mete um item na fila. id = chave de idempotência (uuid gerado no toque).
export async function enfileirar(item: {
  id: string;
  autorizacao_id: string;
  tipo: string;
  momento: string;
  foto_b64: string;
}): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `insert or ignore into outbox_item
       (id, autorizacao_id, tipo, momento, foto_b64, estado, tentativas, criado_em)
     values (?, ?, ?, ?, ?, 'pendente', 0, ?)`,
    item.id, item.autorizacao_id, item.tipo, item.momento, item.foto_b64,
    new Date().toISOString(),
  );
}

export async function contarPendentes(): Promise<number> {
  const db = await getDb();
  const row = await db.getFirstAsync<{ n: number }>(
    `select count(*) as n from outbox_item`,
  );
  return row?.n ?? 0;
}

async function porDrenar(): Promise<Linha[]> {
  const db = await getDb();
  return db.getAllAsync<Linha>(
    `select * from outbox_item order by criado_em asc`,
  );
}

function eDuplicadoStorage(err: any): boolean {
  // re-upload de um item já enviado (após sucesso parcial): tratar como OK
  const msg = String(err?.message ?? '').toLowerCase();
  return msg.includes('exists') || err?.statusCode === '409' || err?.status === 409;
}

let aDrenar = false;

// Tenta enviar todos os itens pendentes. O próprio drain É o teste de rede:
// se falhar, o item fica e tenta-se no próximo gatilho. Seguro chamar a qualquer
// momento; nunca corre duas vezes em paralelo.
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
          const { data, error } = await supabase.rpc('registar_picagem', {
            p_autorizacao_id: it.autorizacao_id,
            p_tipo: it.tipo,
            p_momento_dispositivo: it.momento,
            p_chave_idempotencia: it.id,
          });
          if (error || !data?.foto_path) {
            await db.runAsync(
              `update outbox_item set tentativas = tentativas + 1, erro = ? where id = ?`,
              error?.message ?? 'registo sem caminho', it.id,
            );
            continue; // próximo gatilho tentará de novo
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

          // concluído: apaga o item (os bytes da foto saem com a linha)
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
  } finally {
    aDrenar = false;
  }
}
