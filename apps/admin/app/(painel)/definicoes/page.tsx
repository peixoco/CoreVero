"use client";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type Loja = { id: string; nome: string };
type Kiosk = {
  id: string;
  loja_id: string;
  ativo: boolean;
  revogado_em: string | null;
};

function idCurto(id: string) {
  return id.slice(0, 8);
}

export default function Definicoes() {
  const [lojas, setLojas] = useState<Loja[] | null>(null);
  const [kiosks, setKiosks] = useState<Kiosk[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  // alvo de revogação + texto de confirmação (escrever o nome da loja)
  const [alvo, setAlvo] = useState<{ kiosk: Kiosk; loja: Loja } | null>(null);
  const [confirmTexto, setConfirmTexto] = useState("");
  const [aProcessar, setAProcessar] = useState(false);

  const carregar = useCallback(async () => {
    setErro(null);
    const [l, k] = await Promise.all([
      supabase.from("loja").select("id, nome").order("nome"),
      supabase.from("kiosk").select("id, loja_id, ativo, revogado_em"),
    ]);
    if (l.error) return setErro(l.error.message);
    if (k.error) return setErro(k.error.message);
    setLojas(l.data as Loja[]);
    setKiosks(k.data as Kiosk[]);
  }, []);

  useEffect(() => {
    carregar();
  }, [carregar]);

  async function revogar() {
    if (!alvo) return;
    setAProcessar(true);
    const { error } = await supabase.rpc("revogar_kiosk", {
      p_kiosk_id: alvo.kiosk.id,
    });
    setAProcessar(false);
    if (error) return setErro(error.message);
    setAlvo(null);
    setConfirmTexto("");
    carregar();
  }

  async function reativar(k: Kiosk) {
    setAProcessar(true);
    const { error } = await supabase.rpc("reativar_kiosk", { p_kiosk_id: k.id });
    setAProcessar(false);
    if (error) return setErro(error.message);
    carregar();
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-2">Definições</h1>
      <p className="text-cinza mb-6">
        Dispositivos (kiosks) aprovados por loja. Revogar um kiosk corta-lhe de
        imediato a capacidade de picar e de sincronizar.
      </p>

      {erro && <p className="text-red-600 mb-4">{erro}</p>}

      {!lojas || !kiosks ? (
        <p className="text-cinza">A carregar…</p>
      ) : (
        <div className="space-y-6">
          {lojas.map((loja) => {
            const doLoja = kiosks.filter((k) => k.loja_id === loja.id);
            return (
              <section
                key={loja.id}
                className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden"
              >
                <div className="px-4 py-3 border-b border-black/5 bg-papel/40">
                  <h2 className="font-semibold text-tinta">{loja.nome}</h2>
                </div>

                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-cinza border-b border-black/5">
                      <th className="px-4 py-3 font-medium">Dispositivo</th>
                      <th className="px-4 py-3 font-medium">Estado</th>
                      <th className="px-4 py-3 font-medium">Revogado em</th>
                      <th className="px-4 py-3 font-medium text-right">Ação</th>
                    </tr>
                  </thead>
                  <tbody>
                    {doLoja.map((k) => (
                      <tr
                        key={k.id}
                        className="border-b border-black/5 last:border-0"
                      >
                        <td className="px-4 py-3 font-mono text-tinta">
                          Kiosk · {idCurto(k.id)}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs ${k.ativo ? "bg-teal/10 text-teal" : "bg-red-100 text-red-700"}`}
                          >
                            {k.ativo ? "ativo" : "revogado"}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-cinza">
                          {k.revogado_em
                            ? new Date(k.revogado_em).toLocaleString("pt-PT", {
                                timeZone: "Europe/Lisbon",
                              })
                            : "—"}
                        </td>
                        <td className="px-4 py-3 text-right">
                          {k.ativo ? (
                            <button
                              onClick={() => {
                                setAlvo({ kiosk: k, loja });
                                setConfirmTexto("");
                              }}
                              className="rounded-lg border border-red-300 text-red-700 px-3 py-1.5 text-sm font-medium hover:bg-red-50 transition"
                            >
                              Revogar
                            </button>
                          ) : (
                            <button
                              onClick={() => reativar(k)}
                              disabled={aProcessar}
                              className="rounded-lg border border-teal text-teal px-3 py-1.5 text-sm font-medium hover:bg-teal/5 transition disabled:opacity-50"
                            >
                              Reativar
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                    {doLoja.length === 0 && (
                      <tr>
                        <td colSpan={4} className="px-4 py-6 text-cinza">
                          Sem dispositivos aprovados nesta loja.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </section>
            );
          })}
        </div>
      )}

      {/* Modal de confirmação — escrever o nome da loja */}
      {alvo && (
        <div className="fixed inset-0 bg-tinta/50 grid place-items-center p-4 z-50">
          <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-bold text-tinta mb-2">Revogar kiosk</h3>
            <p className="text-sm text-cinza mb-4">
              Isto corta de imediato a capacidade deste dispositivo de picar e de
              sincronizar picagens ainda por enviar. Picagens guardadas no
              dispositivo e ainda não enviadas{" "}
              <strong className="text-tinta">serão perdidas</strong>. A ação é
              reversível (Reativar), mas o que se perder no intervalo não volta.
            </p>
            <p className="text-sm text-tinta mb-2">
              Para confirmar, escreve o nome da loja:{" "}
              <strong>{alvo.loja.nome}</strong>
            </p>
            <input
              autoFocus
              value={confirmTexto}
              onChange={(e) => setConfirmTexto(e.target.value)}
              placeholder={alvo.loja.nome}
              className="w-full border border-black/10 rounded-lg px-3 py-2 mb-4"
            />
            <div className="flex justify-end gap-2">
              <button
                onClick={() => {
                  setAlvo(null);
                  setConfirmTexto("");
                }}
                className="rounded-lg px-4 py-2 text-sm font-medium text-cinza hover:bg-papel transition"
              >
                Cancelar
              </button>
              <button
                onClick={revogar}
                disabled={confirmTexto.trim() !== alvo.loja.nome || aProcessar}
                className="rounded-lg bg-red-600 text-white px-4 py-2 text-sm font-medium hover:brightness-110 transition disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {aProcessar ? "A revogar…" : "Revogar kiosk"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
