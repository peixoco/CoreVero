"use client";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type Picagem = {
  picagem_id: string;
  tipo: string;
  momento_dispositivo: string;
  trabalhador_nome: string;
  codigo_pessoal: string;
  loja_nome: string;
  foto_url: string;
};

type Recusa = {
  id: string;
  tipo: string;
  momento_dispositivo: string;
  codigo_pessoal: string | null;
  motivo: string;
  criada_em: string;
};

const TIPO_LABEL: Record<string, string> = {
  entrada: "Entrada",
  saida: "Saída",
  inicio_intervalo: "Início intervalo",
  fim_intervalo: "Fim intervalo",
};

function fmt(ts: string) {
  return new Date(ts).toLocaleString("pt-PT", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "Europe/Lisbon",
  });
}

export default function Picagens() {
  const [linhas, setLinhas] = useState<Picagem[] | null>(null);
  const [recusas, setRecusas] = useState<Recusa[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    supabase
      .from("vista_picagem")
      .select(
        "picagem_id, tipo, momento_dispositivo, trabalhador_nome, codigo_pessoal, loja_nome, foto_url",
      )
      .order("momento_dispositivo", { ascending: false })
      .limit(100)
      .then(({ data, error }) => {
        if (error) setErro(error.message);
        else setLinhas(data as Picagem[]);
      });

    supabase
      .from("picagem_recusada")
      .select("id, tipo, momento_dispositivo, codigo_pessoal, motivo, criada_em")
      .order("criada_em", { ascending: false })
      .limit(50)
      .then(({ data }) => {
        if (data) setRecusas(data as Recusa[]);
      });
  }, []);

  async function verFoto(path: string) {
    const { data, error } = await supabase.storage
      .from("picagens")
      .createSignedUrl(path, 60);
    if (error) {
      alert("Não foi possível abrir a foto: " + error.message);
      return;
    }
    window.open(data.signedUrl, "_blank");
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-6">Picagens</h1>
      {erro && <p className="text-red-600 mb-4">{erro}</p>}

      {/* Painel de recusas — só aparece quando há. Tentativas offline rejeitadas
          no servidor (cache obsoleta): não são picagens válidas, pedem atenção. */}
      {recusas.length > 0 && (
        <div className="mb-6 rounded-xl border border-red-300 bg-red-50 overflow-hidden">
          <div className="px-4 py-3 border-b border-red-200">
            <h2 className="font-semibold text-red-800">
              Picagens recusadas ({recusas.length})
            </h2>
            <p className="text-sm text-red-700">
              Tentativas offline rejeitadas pelo servidor (ex.: colaborador
              desativado entretanto). Não foram registadas como picagens —
              confirme com o colaborador.
            </p>
          </div>
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-red-700 border-b border-red-200">
                <th className="px-4 py-2 font-medium">Hora do toque</th>
                <th className="px-4 py-2 font-medium">Código</th>
                <th className="px-4 py-2 font-medium">Tipo</th>
                <th className="px-4 py-2 font-medium">Motivo</th>
                <th className="px-4 py-2 font-medium">Reportada</th>
              </tr>
            </thead>
            <tbody>
              {recusas.map((r) => (
                <tr key={r.id} className="border-b border-red-200 last:border-0">
                  <td className="px-4 py-2 text-tinta">{fmt(r.momento_dispositivo)}</td>
                  <td className="px-4 py-2 text-tinta">{r.codigo_pessoal ?? "—"}</td>
                  <td className="px-4 py-2">{TIPO_LABEL[r.tipo] ?? r.tipo}</td>
                  <td className="px-4 py-2 text-red-700">{r.motivo}</td>
                  <td className="px-4 py-2 text-cinza">{fmt(r.criada_em)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {!linhas ? (
        <p className="text-cinza">A carregar…</p>
      ) : (
        <div className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-cinza border-b border-black/5">
                <th className="px-4 py-3 font-medium">Data / hora</th>
                <th className="px-4 py-3 font-medium">Colaborador</th>
                <th className="px-4 py-3 font-medium">Loja</th>
                <th className="px-4 py-3 font-medium">Tipo</th>
                <th className="px-4 py-3 font-medium">Foto</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <tr
                  key={l.picagem_id}
                  className="border-b border-black/5 last:border-0 hover:bg-papel/50"
                >
                  <td className="px-4 py-3">{fmt(l.momento_dispositivo)}</td>
                  <td className="px-4 py-3">
                    {l.trabalhador_nome}{" "}
                    <span className="text-cinza">({l.codigo_pessoal})</span>
                  </td>
                  <td className="px-4 py-3 text-cinza">{l.loja_nome}</td>
                  <td className="px-4 py-3">{TIPO_LABEL[l.tipo] ?? l.tipo}</td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => verFoto(l.foto_url)}
                      className="text-teal hover:underline"
                    >
                      ver foto
                    </button>
                  </td>
                </tr>
              ))}
              {linhas.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-6 text-cinza">
                    Sem picagens ainda.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
