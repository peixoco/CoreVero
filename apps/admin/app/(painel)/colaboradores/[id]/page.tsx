"use client";
import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";

const TIPO_LABEL: Record<string, string> = {
  entrada: "Entrada",
  saida: "Saída",
  inicio_intervalo: "Início intervalo",
  fim_intervalo: "Fim intervalo",
};
const TIPOS = ["entrada", "saida", "inicio_intervalo", "fim_intervalo"];

type Picagem = {
  picagem_id: string;
  tipo: string;
  momento_dispositivo: string;
  anulada: boolean;
  motivo_anulacao: string | null;
  correcao_manual: boolean;
};
type Horas = {
  seg_trabalho: number;
  seg_pausa: number;
  turnos: number;
  incompleto: boolean;
  todos_fechados: boolean;
} | null;

// Hoje em Lisboa (YYYY-MM-DD)
function hojeLisboa() {
  return new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Lisbon" });
}
// Data de Lisboa de um instante (YYYY-MM-DD)
function diaLisboa(ts: string) {
  return new Date(ts).toLocaleDateString("en-CA", { timeZone: "Europe/Lisbon" });
}
// Hora de Lisboa (HH:MM)
function horaLisboa(ts: string) {
  return new Date(ts).toLocaleTimeString("pt-PT", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Europe/Lisbon",
  });
}
// Converte (data + hora de parede de Lisboa) -> ISO UTC correto, com DST.
function paredeParaUTC(data: string, hora: string) {
  const naive = new Date(`${data}T${hora}:00Z`);
  const lis = new Date(naive.toLocaleString("en-US", { timeZone: "Europe/Lisbon" }));
  const utc = new Date(naive.toLocaleString("en-US", { timeZone: "UTC" }));
  return new Date(naive.getTime() - (lis.getTime() - utc.getTime())).toISOString();
}
function hm(seg: number) {
  const h = Math.floor(seg / 3600);
  const m = Math.round((seg % 3600) / 60);
  return `${h}h ${String(m).padStart(2, "0")}m`;
}

export default function Colaborador() {
  const { id } = useParams<{ id: string }>();
  const [nome, setNome] = useState<string | null>(null);
  const [tab, setTab] = useState(0);

  const [dia, setDia] = useState(hojeLisboa());
  const [picagens, setPicagens] = useState<Picagem[]>([]);
  const [horas, setHoras] = useState<Horas>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // form adicionar
  const [novoTipo, setNovoTipo] = useState("entrada");
  const [novaHora, setNovaHora] = useState("09:00");

  useEffect(() => {
    if (!id) return;
    supabase.from("trabalhador").select("nome").eq("id", id).maybeSingle()
      .then(({ data }) => setNome((data as { nome: string } | null)?.nome ?? "—"));
  }, [id]);

  const carregarDia = useCallback(() => {
    if (!id) return;
    setErro(null);
    const base = new Date(`${dia}T12:00:00Z`);
    const ini = new Date(base); ini.setUTCDate(base.getUTCDate() - 1);
    const fim = new Date(base); fim.setUTCDate(base.getUTCDate() + 1);

    supabase
      .from("vista_picagem")
      .select("picagem_id, tipo, momento_dispositivo, anulada, motivo_anulacao, correcao_manual")
      .eq("trabalhador_id", id)
      .gte("momento_dispositivo", ini.toISOString())
      .lte("momento_dispositivo", fim.toISOString())
      .order("momento_dispositivo")
      .then(({ data, error }) => {
        if (error) return setErro(error.message);
        setPicagens(((data as Picagem[]) ?? []).filter((p) => diaLisboa(p.momento_dispositivo) === dia));
      });

    supabase
      .from("vista_horas_dia")
      .select("seg_trabalho, seg_pausa, turnos, incompleto, todos_fechados")
      .eq("trabalhador_id", id)
      .eq("dia", dia)
      .maybeSingle()
      .then(({ data }) => setHoras(data as Horas));
  }, [id, dia]);

  useEffect(() => { carregarDia(); }, [carregarDia]);

  async function anular(p: Picagem) {
    const motivo = window.prompt(
      `Anular a ${TIPO_LABEL[p.tipo] ?? p.tipo} das ${horaLisboa(p.momento_dispositivo)}?\nMotivo:`,
    );
    if (motivo === null) return;
    setBusy(true);
    const { error } = await supabase.rpc("anular_picagem", { p_picagem_id: p.picagem_id, p_motivo: motivo });
    setBusy(false);
    if (error) return setErro(error.message);
    carregarDia();
  }

  async function adicionar() {
    setBusy(true);
    const momento = paredeParaUTC(dia, novaHora);
    const { error } = await supabase.rpc("corrigir_picagem", {
      p_trabalhador_id: id,
      p_tipo: novoTipo,
      p_momento: momento,
      p_motivo: "correção manual",
    });
    setBusy(false);
    if (error) return setErro(error.message);
    carregarDia();
  }

  const TABS = ["Informação", "PIN / Picagem", "Documentos", "Horário", "Férias"];

  return (
    <div>
      <Link href="/colaboradores" className="text-sm text-cinza hover:text-tinta">
        ← Colaboradores
      </Link>
      <h1 className="text-2xl font-bold mt-2 mb-4">{nome ?? "…"}</h1>

      <div className="flex gap-1 border-b border-black/10 mb-6">
        {TABS.map((t, i) => (
          <button
            key={t}
            onClick={() => setTab(i)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === i ? "border-teal text-tinta" : "border-transparent text-cinza hover:text-tinta"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 1 ? (
        <div>
          {erro && <p className="text-red-600 mb-4">{erro}</p>}

          <div className="flex items-center gap-3 mb-4">
            <label className="text-sm text-cinza">Dia</label>
            <input
              type="date"
              value={dia}
              onChange={(e) => setDia(e.target.value)}
              className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
            />
            {horas && (
              <span className="text-sm text-tinta">
                <strong>{hm(horas.seg_trabalho)}</strong> de trabalho
                {horas.seg_pausa > 0 && <> · pausa {hm(horas.seg_pausa)}</>}
                {" · "}{horas.turnos} turno{horas.turnos !== 1 ? "s" : ""}
                {horas.incompleto && (
                  <span className="ml-2 rounded-full bg-amber-100 text-amber-800 text-xs px-2 py-0.5">
                    incompleto
                  </span>
                )}
              </span>
            )}
          </div>

          <div className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden mb-4">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-cinza border-b border-black/5">
                  <th className="px-4 py-2 font-medium">Hora</th>
                  <th className="px-4 py-2 font-medium">Tipo</th>
                  <th className="px-4 py-2 font-medium"></th>
                  <th className="px-4 py-2 font-medium text-right">Ação</th>
                </tr>
              </thead>
              <tbody>
                {picagens.map((p) => (
                  <tr
                    key={p.picagem_id}
                    className={`border-b border-black/5 last:border-0 ${p.anulada ? "opacity-50" : ""}`}
                  >
                    <td className={`px-4 py-2 ${p.anulada ? "line-through" : ""}`}>
                      {horaLisboa(p.momento_dispositivo)}
                    </td>
                    <td className={`px-4 py-2 ${p.anulada ? "line-through" : ""}`}>
                      {TIPO_LABEL[p.tipo] ?? p.tipo}
                    </td>
                    <td className="px-4 py-2">
                      <div className="flex gap-1">
                        {p.correcao_manual && (
                          <span className="rounded-full bg-cinza/15 text-cinza text-xs px-2 py-0.5">manual</span>
                        )}
                        {p.anulada && (
                          <span
                            className="rounded-full bg-red-100 text-red-700 text-xs px-2 py-0.5"
                            title={p.motivo_anulacao ?? ""}
                          >
                            anulada
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-2 text-right">
                      {!p.anulada && (
                        <button
                          onClick={() => anular(p)}
                          disabled={busy}
                          className="rounded-lg border border-red-300 text-red-700 px-3 py-1 text-xs font-medium hover:bg-red-50 transition disabled:opacity-50"
                        >
                          Anular
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
                {picagens.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-cinza">
                      Sem picagens neste dia.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="rounded-xl border border-black/10 bg-papel/40 p-4">
            <p className="text-sm font-medium text-tinta mb-3">Adicionar picagem em falta</p>
            <div className="flex flex-wrap items-end gap-3">
              <div>
                <label className="block text-xs text-cinza mb-1">Tipo</label>
                <select
                  value={novoTipo}
                  onChange={(e) => setNovoTipo(e.target.value)}
                  className="rounded-lg border border-black/15 px-3 py-1.5 text-sm bg-white"
                >
                  {TIPOS.map((t) => (
                    <option key={t} value={t}>{TIPO_LABEL[t]}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs text-cinza mb-1">Hora</label>
                <input
                  type="time"
                  value={novaHora}
                  onChange={(e) => setNovaHora(e.target.value)}
                  className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
                />
              </div>
              <button
                onClick={adicionar}
                disabled={busy}
                className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50"
              >
                Adicionar
              </button>
            </div>
            <p className="text-xs text-cinza mt-2">
              Fica registada como correção manual, com o teu nome e a hora indicada.
            </p>
          </div>
        </div>
      ) : (
        <div className="rounded-xl border border-dashed border-black/15 bg-papel/40 p-8 text-center">
          <div className="flex items-center justify-center gap-2 mb-2">
            <p className="font-semibold text-tinta">{TABS[tab]}</p>
            <span className="rounded-full bg-cinza/15 text-cinza text-xs px-2 py-0.5">em construção</span>
          </div>
          <p className="text-sm text-cinza max-w-md mx-auto">
            Esta tab depende da camada de dados de RH (dados fiscais cifrados,
            documentos, horário, férias). Frente C do roadmap.
          </p>
        </div>
      )}
    </div>
  );
}
