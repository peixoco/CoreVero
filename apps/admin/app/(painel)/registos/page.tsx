"use client";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type Tab = "picagens" | "checklists" | "validacoes";

type Picagem = {
  picagem_id: string;
  tipo: string;
  momento_dispositivo: string;
  trabalhador_nome: string;
  codigo_pessoal: string;
  loja_nome: string;
  foto_url: string | null;
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

export default function Registos() {
  const [tab, setTab] = useState<Tab>("picagens");
  const [linhas, setLinhas] = useState<Picagem[] | null>(null);
  const [recusas, setRecusas] = useState<Recusa[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [aProcessar, setAProcessar] = useState<string | null>(null);

  const carregarPicagens = useCallback(() => {
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
  }, []);

  const carregarRecusas = useCallback(() => {
    supabase
      .from("picagem_recusada")
      .select("id, tipo, momento_dispositivo, codigo_pessoal, motivo, criada_em")
      .eq("estado", "pendente")
      .order("criada_em", { ascending: false })
      .limit(50)
      .then(({ data }) => {
        if (data) setRecusas(data as Recusa[]);
      });
  }, []);

  useEffect(() => {
    carregarPicagens();
    carregarRecusas();
  }, [carregarPicagens, carregarRecusas]);

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

  async function aceitar(r: Recusa) {
    if (
      !window.confirm(
        "Aceitar cria uma picagem real (correção manual, sem foto) com a hora original. Continuar?",
      )
    )
      return;
    setAProcessar(r.id);
    const { error } = await supabase.rpc("aceitar_recusa", { p_recusa_id: r.id });
    setAProcessar(null);
    if (error) return setErro(error.message);
    carregarRecusas();
    carregarPicagens();
  }

  async function descartar(r: Recusa) {
    if (!window.confirm("Descartar esta recusa? Não cria nenhuma picagem.")) return;
    setAProcessar(r.id);
    const { error } = await supabase.rpc("descartar_recusa", { p_recusa_id: r.id });
    setAProcessar(null);
    if (error) return setErro(error.message);
    carregarRecusas();
  }

  const TABS: { id: Tab; label: string }[] = [
    { id: "picagens", label: "Picagens" },
    { id: "checklists", label: "Checklists" },
    { id: "validacoes", label: "Validações" },
  ];

  return (
    <div>
      <h1 className="text-2xl font-bold mb-4">Registos</h1>

      <div className="flex gap-1 border-b border-black/10 mb-6">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === t.id
                ? "border-teal text-tinta"
                : "border-transparent text-cinza hover:text-tinta"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {erro && <p className="text-red-600 mb-4">{erro}</p>}

      {tab === "picagens" && (
        <>
          {recusas.length > 0 && (
            <div className="mb-6 rounded-xl border border-red-300 bg-red-50 overflow-hidden">
              <div className="px-4 py-3 border-b border-red-200">
                <h2 className="font-semibold text-red-800">
                  Picagens recusadas ({recusas.length})
                </h2>
                <p className="text-sm text-red-700">
                  Tentativas offline rejeitadas (ex.: colaborador desativado
                  entretanto). <strong>Aceitar</strong> cria a picagem com a hora
                  original (correção manual, sem foto). <strong>Descartar</strong>{" "}
                  resolve sem criar nada.
                </p>
              </div>
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-red-700 border-b border-red-200">
                    <th className="px-4 py-2 font-medium">Hora do toque</th>
                    <th className="px-4 py-2 font-medium">Código</th>
                    <th className="px-4 py-2 font-medium">Tipo</th>
                    <th className="px-4 py-2 font-medium">Motivo</th>
                    <th className="px-4 py-2 font-medium text-right">Ação</th>
                  </tr>
                </thead>
                <tbody>
                  {recusas.map((r) => (
                    <tr key={r.id} className="border-b border-red-200 last:border-0">
                      <td className="px-4 py-2 text-tinta">{fmt(r.momento_dispositivo)}</td>
                      <td className="px-4 py-2 text-tinta">{r.codigo_pessoal ?? "—"}</td>
                      <td className="px-4 py-2">{TIPO_LABEL[r.tipo] ?? r.tipo}</td>
                      <td className="px-4 py-2 text-red-700">{r.motivo}</td>
                      <td className="px-4 py-2">
                        <div className="flex justify-end gap-2">
                          <button
                            onClick={() => aceitar(r)}
                            disabled={aProcessar === r.id}
                            className="rounded-lg border border-teal text-teal px-3 py-1 text-sm font-medium hover:bg-teal/5 transition disabled:opacity-50"
                          >
                            Aceitar
                          </button>
                          <button
                            onClick={() => descartar(r)}
                            disabled={aProcessar === r.id}
                            className="rounded-lg border border-red-300 text-red-700 px-3 py-1 text-sm font-medium hover:bg-red-100 transition disabled:opacity-50"
                          >
                            Descartar
                          </button>
                        </div>
                      </td>
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
                        {l.foto_url ? (
                          <button
                            onClick={() => verFoto(l.foto_url as string)}
                            className="text-teal hover:underline"
                          >
                            ver foto
                          </button>
                        ) : (
                          <span className="text-cinza text-xs rounded-full bg-cinza/15 px-2 py-0.5">
                            correção manual
                          </span>
                        )}
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
        </>
      )}

      {tab === "checklists" && (
        <Placeholder
          titulo="Checklists HACCP"
          desc="O módulo de monitorização HACCP (construtor de templates + motor de conformidade) entra aqui. Frente B do roadmap."
        />
      )}

      {tab === "validacoes" && (
        <Placeholder
          titulo="Validações"
          desc="Exportar/importar as horas em xlsx por dia, semana ou mês, para verificar e corrigir. Depende do cálculo de horas (Frente A)."
        />
      )}
    </div>
  );
}

function Placeholder({ titulo, desc }: { titulo: string; desc: string }) {
  return (
    <div className="rounded-xl border border-dashed border-black/15 bg-papel/40 p-8 text-center">
      <div className="flex items-center justify-center gap-2 mb-2">
        <p className="font-semibold text-tinta">{titulo}</p>
        <span className="rounded-full bg-cinza/15 text-cinza text-xs px-2 py-0.5">
          em breve
        </span>
      </div>
      <p className="text-sm text-cinza max-w-md mx-auto">{desc}</p>
    </div>
  );
}
