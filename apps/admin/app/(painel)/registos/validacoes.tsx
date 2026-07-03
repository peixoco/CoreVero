"use client";
import { useEffect, useRef, useState } from "react";
import * as XLSX from "xlsx";
import { supabase } from "@/lib/supabase";

type Trab = { id: string; nome: string; codigo_pessoal: string };
type LinhaFolha = {
  codigo: string; data: string;
  entrada: string; inicio_pausa: string; fim_pausa: string; saida: string;
};
type Detalhe = { codigo: string; data: string; tipo: string; accao: string; de?: string; para: string };
type Resultado = {
  simulado: boolean; adicionar: number; substituir: number; sem_alteracao: number;
  complexos: { codigo: string; data: string }[];
  erros: { linha: number; codigo: string; data: string; erro: string }[];
  detalhes: Detalhe[];
};

const TIPO_SLOT: Record<string, keyof LinhaFolha> = {
  entrada: "entrada",
  inicio_intervalo: "inicio_pausa",
  fim_intervalo: "fim_pausa",
  saida: "saida",
};
const SLOT_LABEL: Record<string, string> = {
  entrada: "Entrada", inicio_pausa: "Início pausa", fim_pausa: "Fim pausa", saida: "Saída",
};
const HEADER = ["codigo", "nome", "data", "entrada", "inicio_pausa", "fim_pausa", "saida"];

function diaLisboa(ts: string) {
  return new Date(ts).toLocaleDateString("en-CA", { timeZone: "Europe/Lisbon" });
}
function horaLisboa(ts: string) {
  return new Date(ts).toLocaleTimeString("pt-PT", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Lisbon" });
}
function hojeLisboa() {
  return new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Lisbon" });
}
function diasAtras(n: number) {
  const d = new Date(); d.setDate(d.getDate() - n);
  return d.toLocaleDateString("en-CA", { timeZone: "Europe/Lisbon" });
}
function diasEntre(ini: string, fim: string) {
  const out: string[] = [];
  const d = new Date(`${ini}T12:00:00Z`);
  const end = new Date(`${fim}T12:00:00Z`);
  while (d <= end) {
    out.push(d.toLocaleDateString("en-CA", { timeZone: "UTC" }));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}
function normData(v: unknown): string {
  if (v == null) return "";
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  const s = String(v).trim();
  const m = s.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}`;
  return s;
}
function normHora(v: unknown): string {
  if (v == null) return "";
  if (v instanceof Date) return v.toISOString().slice(11, 16);
  const s = String(v).trim();
  if (s === "") return "";
  if (/^0?\.\d+$/.test(s)) {
    const mins = Math.round(parseFloat(s) * 24 * 60);
    return `${String(Math.floor(mins / 60)).padStart(2, "0")}:${String(mins % 60).padStart(2, "0")}`;
  }
  const m = s.match(/^(\d{1,2}):(\d{2})/);
  if (m) return `${m[1].padStart(2, "0")}:${m[2]}`;
  return s;
}

export default function Validacoes() {
  const [trabs, setTrabs] = useState<Trab[]>([]);
  const [colab, setColab] = useState("todos");
  const [ini, setIni] = useState(diasAtras(7));
  const [fim, setFim] = useState(hojeLisboa());
  const [erro, setErro] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [linhas, setLinhas] = useState<LinhaFolha[] | null>(null); // parsed do import
  const [preview, setPreview] = useState<Resultado | null>(null);
  const [feito, setFeito] = useState<Resultado | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.from("trabalhador").select("id, nome, codigo_pessoal").eq("ativo", true).order("nome")
      .then(({ data }) => setTrabs((data as Trab[]) ?? []));
  }, []);

  async function exportar() {
    setErro(null); setBusy(true);
    const s = new Date(`${ini}T00:00:00Z`); s.setUTCDate(s.getUTCDate() - 1);
    const e = new Date(`${fim}T00:00:00Z`); e.setUTCDate(e.getUTCDate() + 2);

    let q = supabase
      .from("vista_picagem")
      .select("tipo, momento_dispositivo, trabalhador_id, anulada")
      .gte("momento_dispositivo", s.toISOString())
      .lte("momento_dispositivo", e.toISOString())
      .order("momento_dispositivo");
    if (colab !== "todos") q = q.eq("trabalhador_id", colab);

    const { data, error } = await q;
    setBusy(false);
    if (error) return setErro(error.message);

    // agrupar por trabalhador + dia (primeira de cada tipo)
    const grupos: Record<string, Partial<LinhaFolha>> = {};
    for (const p of (data as Record<string, unknown>[]) ?? []) {
      if (p.anulada) continue;
      const dia = diaLisboa(p.momento_dispositivo as string);
      if (dia < ini || dia > fim) continue;
      const k = `${p.trabalhador_id}|${dia}`;
      grupos[k] ??= {};
      const slot = TIPO_SLOT[p.tipo as string];
      if (slot && !grupos[k][slot]) grupos[k][slot] = horaLisboa(p.momento_dispositivo as string);
    }

    const selec = colab === "todos" ? trabs : trabs.filter((t) => t.id === colab);
    const dias = diasEntre(ini, fim);
    const rows: Record<string, string>[] = [];
    for (const t of selec) {
      for (const dia of dias) {
        const g = grupos[`${t.id}|${dia}`] ?? {};
        rows.push({
          codigo: t.codigo_pessoal, nome: t.nome, data: dia,
          entrada: g.entrada ?? "", inicio_pausa: g.inicio_pausa ?? "",
          fim_pausa: g.fim_pausa ?? "", saida: g.saida ?? "",
        });
      }
    }

    const ws = XLSX.utils.json_to_sheet(rows, { header: HEADER });
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "folha");
    XLSX.writeFile(wb, `folha_${ini}_a_${fim}.xlsx`);
  }

  async function lerFicheiro(file: File) {
    setErro(null); setPreview(null); setFeito(null); setLinhas(null); setBusy(true);
    try {
      const buf = await file.arrayBuffer();
      const wb = XLSX.read(buf, { type: "array" });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const raw = XLSX.utils.sheet_to_json<Record<string, unknown>>(ws, { defval: "" });

      const ls: LinhaFolha[] = raw.map((r) => ({
        codigo: String(r.codigo ?? "").trim(),
        data: normData(r.data),
        entrada: normHora(r.entrada),
        inicio_pausa: normHora(r.inicio_pausa),
        fim_pausa: normHora(r.fim_pausa),
        saida: normHora(r.saida),
      })).filter((l) => l.codigo !== "");

      setLinhas(ls);
      const { data, error } = await supabase.rpc("aplicar_folha", { p_linhas: ls, p_simular: true });
      setBusy(false);
      if (error) return setErro(error.message);
      setPreview(data as Resultado);
    } catch (ex) {
      setBusy(false);
      setErro("Não foi possível ler o ficheiro: " + (ex as Error).message);
    }
  }

  async function aplicar() {
    if (!linhas) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("aplicar_folha", { p_linhas: linhas, p_simular: false });
    setBusy(false);
    if (error) return setErro(error.message);
    setFeito(data as Resultado);
    setPreview(null);
    setLinhas(null);
  }

  function cancelar() {
    setPreview(null); setLinhas(null);
  }

  return (
    <div className="space-y-6">
      <div className="rounded-xl border border-black/10 bg-white p-5 shadow-sm">
        <h2 className="font-semibold text-tinta mb-1">Folha de horas</h2>
        <p className="text-sm text-cinza mb-4">
          Descarrega uma folha do período: uma linha por colaborador por dia. Os dias com
          picagens vêm preenchidos; os em falta vêm em branco. Escreve as horas por cima
          (corrigir) ou preenche os vazios (adicionar) e importa. Célula em branco não mexe em nada.
        </p>
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <label className="block text-xs text-cinza mb-1">Colaborador</label>
            <select value={colab} onChange={(e) => setColab(e.target.value)}
              className="rounded-lg border border-black/15 px-3 py-1.5 text-sm bg-white">
              <option value="todos">Todos</option>
              {trabs.map((t) => <option key={t.id} value={t.id}>{t.nome} ({t.codigo_pessoal})</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs text-cinza mb-1">De</label>
            <input type="date" value={ini} onChange={(e) => setIni(e.target.value)}
              className="rounded-lg border border-black/15 px-3 py-1.5 text-sm" />
          </div>
          <div>
            <label className="block text-xs text-cinza mb-1">Até</label>
            <input type="date" value={fim} onChange={(e) => setFim(e.target.value)}
              className="rounded-lg border border-black/15 px-3 py-1.5 text-sm" />
          </div>
          <button onClick={exportar} disabled={busy}
            className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50">
            Descarregar folha
          </button>
          <button onClick={() => fileRef.current?.click()} disabled={busy}
            className="rounded-lg border border-teal text-teal px-4 py-1.5 text-sm font-medium hover:bg-teal/5 transition disabled:opacity-50">
            Importar folha
          </button>
          <input
            ref={fileRef} type="file" accept=".xlsx,.xls" className="hidden"
            onChange={(e) => { const f = e.target.files?.[0]; if (f) lerFicheiro(f); e.target.value = ""; }}
          />
        </div>

        {busy && <p className="text-cinza text-sm mt-4">A processar…</p>}
        {erro && <p className="text-red-600 text-sm mt-4">{erro}</p>}

        {/* PRÉ-VISUALIZAÇÃO */}
        {preview && (
          <div className="mt-5 rounded-lg border border-black/10 bg-papel/40 p-4">
            <p className="text-sm font-medium text-tinta mb-2">
              {preview.adicionar + preview.substituir === 0
                ? "Nada a alterar."
                : `Vais aplicar: ${preview.adicionar} a adicionar · ${preview.substituir} a substituir`}
              {preview.sem_alteracao > 0 && (
                <span className="text-cinza font-normal"> · {preview.sem_alteracao} já iguais</span>
              )}
            </p>

            {preview.complexos.length > 0 && (
              <p className="text-sm text-amber-800 mb-2">
                {preview.complexos.length} dia(s) complexo(s) ignorado(s) (vários turnos) — edita na ficha:{" "}
                {preview.complexos.map((c) => `${c.codigo}/${c.data}`).join(", ")}
              </p>
            )}
            {preview.erros.length > 0 && (
              <div className="text-sm text-red-700 mb-2">
                <p className="font-medium">{preview.erros.length} erro(s):</p>
                <ul className="list-disc pl-5">
                  {preview.erros.map((e, i) => (
                    <li key={i}>linha {e.linha}{e.codigo ? ` · ${e.codigo}` : ""}{e.data ? ` · ${e.data}` : ""} — {e.erro}</li>
                  ))}
                </ul>
              </div>
            )}

            {preview.detalhes.length > 0 && (
              <div className="max-h-48 overflow-auto rounded border border-black/5 bg-white mb-3">
                <table className="w-full text-xs">
                  <tbody>
                    {preview.detalhes.map((d, i) => (
                      <tr key={i} className="border-b border-black/5 last:border-0">
                        <td className="px-2 py-1 text-cinza">{d.codigo}</td>
                        <td className="px-2 py-1">{d.data}</td>
                        <td className="px-2 py-1">{SLOT_LABEL[TIPO_SLOT[d.tipo]] ?? d.tipo}</td>
                        <td className="px-2 py-1">
                          {d.accao === "substituir"
                            ? <span><span className="line-through text-cinza">{d.de}</span> → <strong>{d.para}</strong></span>
                            : <span className="text-teal">+ {d.para}</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <div className="flex gap-2">
              <button onClick={aplicar} disabled={busy || preview.adicionar + preview.substituir === 0}
                className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50">
                Aplicar alterações
              </button>
              <button onClick={cancelar} disabled={busy}
                className="rounded-lg border border-black/15 text-tinta px-4 py-1.5 text-sm font-medium hover:bg-papel transition">
                Cancelar
              </button>
            </div>
          </div>
        )}

        {/* RESULTADO */}
        {feito && (
          <div className="mt-4 rounded-lg border border-black/10 bg-papel/40 p-4 space-y-2">
            <p className="text-sm font-medium text-teal">
              Aplicado: {feito.adicionar} adicionadas · {feito.substituir} substituídas.
              {feito.sem_alteracao > 0 && (
                <span className="text-cinza font-normal"> · {feito.sem_alteracao} já iguais</span>
              )}
            </p>

            {feito.complexos.length > 0 && (
              <p className="text-sm text-amber-800">
                {feito.complexos.length} dia(s) complexo(s) ignorado(s) (vários turnos) — edita na ficha:{" "}
                {feito.complexos.map((c) => `${c.codigo}/${c.data}`).join(", ")}
              </p>
            )}

            {feito.erros.length > 0 && (
              <div className="text-sm text-red-700">
                <p className="font-medium">{feito.erros.length} erro(s) — estas linhas não foram aplicadas:</p>
                <ul className="list-disc pl-5">
                  {feito.erros.map((e, i) => (
                    <li key={i}>linha {e.linha}{e.codigo ? ` · ${e.codigo}` : ""}{e.data ? ` · ${e.data}` : ""} — {e.erro}</li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
