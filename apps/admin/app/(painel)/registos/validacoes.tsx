"use client";
import { useEffect, useState } from "react";
import * as XLSX from "xlsx";
import { supabase } from "@/lib/supabase";

type Trab = { id: string; nome: string; codigo_pessoal: string };
type LinhaRelatorio = {
  linha: number; acao?: string; ok: boolean; erro?: string; ignorada?: boolean; picagem_id?: string;
};

const TIPO_LABEL: Record<string, string> = {
  entrada: "Entrada", saida: "Saída",
  inicio_intervalo: "Início intervalo", fim_intervalo: "Fim intervalo",
};

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
  const [relatorio, setRelatorio] = useState<LinhaRelatorio[] | null>(null);
  const [busy, setBusy] = useState(false);

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
      .select("picagem_id, tipo, momento_dispositivo, trabalhador_id, trabalhador_nome, codigo_pessoal, anulada")
      .gte("momento_dispositivo", s.toISOString())
      .lte("momento_dispositivo", e.toISOString())
      .order("momento_dispositivo");
    if (colab !== "todos") q = q.eq("trabalhador_id", colab);

    const { data, error } = await q;
    setBusy(false);
    if (error) return setErro(error.message);

    const rows = ((data as Record<string, unknown>[]) ?? [])
      .filter((p) => {
        const d = diaLisboa(p.momento_dispositivo as string);
        return d >= ini && d <= fim;
      })
      .map((p) => ({
        acao: "",
        picagem_id: p.picagem_id as string,
        codigo: p.codigo_pessoal as string,
        nome: p.trabalhador_nome as string,
        data: diaLisboa(p.momento_dispositivo as string),
        hora: horaLisboa(p.momento_dispositivo as string),
        tipo: p.tipo as string,
        anulada: p.anulada ? "sim" : "",
        motivo: "",
      }));

    const ws = XLSX.utils.json_to_sheet(rows, {
      header: ["acao", "picagem_id", "codigo", "nome", "data", "hora", "tipo", "anulada", "motivo"],
    });
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "picagens");
    XLSX.writeFile(wb, `picagens_${ini}_a_${fim}.xlsx`);
  }

  function modelo() {
    const exemplo = [
      { acao: "adicionar", picagem_id: "", codigo: "1001", nome: "(ref.)", data: hojeLisboa(), hora: "09:00", tipo: "entrada", anulada: "", motivo: "esqueceu PIN" },
      { acao: "adicionar", picagem_id: "", codigo: "1001", nome: "(ref.)", data: hojeLisboa(), hora: "18:00", tipo: "saida", anulada: "", motivo: "esqueceu PIN" },
    ];
    const ws = XLSX.utils.json_to_sheet(exemplo, {
      header: ["acao", "picagem_id", "codigo", "nome", "data", "hora", "tipo", "anulada", "motivo"],
    });
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "modelo");
    XLSX.writeFile(wb, "modelo_correcoes.xlsx");
  }

  async function importar(file: File) {
    setErro(null); setRelatorio(null); setBusy(true);
    try {
      const buf = await file.arrayBuffer();
      const wb = XLSX.read(buf, { type: "array" });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const raw = XLSX.utils.sheet_to_json<Record<string, unknown>>(ws, { defval: "" });

      const linhas = raw.map((r) => ({
        acao: String(r.acao ?? "").trim(),
        picagem_id: String(r.picagem_id ?? "").trim() || null,
        codigo: String(r.codigo ?? "").trim(),
        data: normData(r.data),
        hora: normHora(r.hora),
        tipo: String(r.tipo ?? "").trim(),
        motivo: String(r.motivo ?? "").trim(),
      }));

      const { data, error } = await supabase.rpc("aplicar_correcoes", { p_linhas: linhas });
      setBusy(false);
      if (error) return setErro(error.message);
      setRelatorio(data as LinhaRelatorio[]);
    } catch (ex) {
      setBusy(false);
      setErro("Não foi possível ler o ficheiro: " + (ex as Error).message);
    }
  }

  const ok = relatorio?.filter((r) => r.ok && !r.ignorada).length ?? 0;
  const falhas = relatorio?.filter((r) => !r.ok) ?? [];

  return (
    <div className="space-y-6">
      <div className="rounded-xl border border-black/10 bg-white p-5 shadow-sm">
        <h2 className="font-semibold text-tinta mb-1">Exportar picagens</h2>
        <p className="text-sm text-cinza mb-4">
          Descarrega as picagens do período. Para corrigir, preenche a coluna <strong>acao</strong>:
          {" "}<code>substituir</code> (muda a hora da linha), <code>anular</code> (anula a linha),
          {" "}ou acrescenta linhas novas com <code>adicionar</code>. Reimporta em baixo.
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
            Exportar xlsx
          </button>
          <button onClick={modelo} disabled={busy}
            className="rounded-lg border border-black/15 text-tinta px-4 py-1.5 text-sm font-medium hover:bg-papel transition disabled:opacity-50">
            Modelo em branco
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-black/10 bg-white p-5 shadow-sm">
        <h2 className="font-semibold text-tinta mb-1">Importar correções</h2>
        <p className="text-sm text-cinza mb-4">
          Carrega o xlsx editado. Cada linha com <strong>acao</strong> preenchida é aplicada;
          linhas sem acao são ignoradas. Recebes um relatório por linha.
        </p>
        <input
          type="file"
          accept=".xlsx,.xls"
          disabled={busy}
          onChange={(e) => { const f = e.target.files?.[0]; if (f) importar(f); e.target.value = ""; }}
          className="text-sm"
        />
        {busy && <p className="text-cinza text-sm mt-3">A processar…</p>}
        {erro && <p className="text-red-600 text-sm mt-3">{erro}</p>}

        {relatorio && (
          <div className="mt-4">
            <p className="text-sm mb-2">
              <span className="font-medium text-teal">{ok} aplicadas</span>
              {falhas.length > 0 && <span className="text-red-600"> · {falhas.length} com erro</span>}
            </p>
            {falhas.length > 0 && (
              <div className="rounded-lg border border-red-200 bg-red-50 overflow-hidden">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-red-700 border-b border-red-200">
                      <th className="px-3 py-2 font-medium">Linha</th>
                      <th className="px-3 py-2 font-medium">Erro</th>
                    </tr>
                  </thead>
                  <tbody>
                    {falhas.map((f) => (
                      <tr key={f.linha} className="border-b border-red-200 last:border-0">
                        <td className="px-3 py-2 text-tinta">{f.linha}</td>
                        <td className="px-3 py-2 text-red-700">{f.erro}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
