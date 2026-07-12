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

const AREAS = ["cozinha", "sala", "copa", "bar", "economato", "escritório"];
const inp =
  "w-full rounded-lg border border-black/15 bg-white px-3 py-2 text-sm outline-none focus:border-teal focus:ring-2 focus:ring-teal/20";

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

  // PIN: novo PIN vive só neste ecrã, mascarado por defeito, mostrado uma única vez.
  const [novoPin, setNovoPin] = useState<string | null>(null);
  const [pinVisivel, setPinVisivel] = useState(false);

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

  async function regenerarPin() {
    if (
      !window.confirm(
        "Gerar um novo PIN? O PIN atual deixa de funcionar imediatamente e o novo só é mostrado uma vez.",
      )
    )
      return;
    setErro(null);
    setNovoPin(null);
    setPinVisivel(false);
    setBusy(true);
    const { data, error } = await supabase.rpc("gerar_novo_pin", { p_trabalhador_id: id });
    setBusy(false);
    if (error) return setErro(error.message);
    setNovoPin(data as string);
  }

  function mudarTab(i: number) {
    // O novo PIN nunca sobrevive à saída do ecrã onde foi mostrado.
    setNovoPin(null);
    setPinVisivel(false);
    setErro(null);
    setTab(i);
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
            onClick={() => mudarTab(i)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === i ? "border-teal text-tinta" : "border-transparent text-cinza hover:text-tinta"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 0 ? (
        <InformacaoTab id={id} onNome={setNome} />
      ) : tab === 1 ? (
        <div>
          {erro && <p className="text-red-600 mb-4">{erro}</p>}

          <div className="bg-white rounded-xl border border-black/5 shadow-sm p-4 mb-6">
            <p className="text-sm font-medium text-tinta mb-1">PIN de picagem</p>
            <p className="text-xs text-cinza mb-3">
              O PIN nunca é recuperável: só é mostrado uma vez, ao ser gerado.
            </p>
            <div className="flex flex-wrap items-center gap-3">
              <button
                onClick={regenerarPin}
                disabled={busy}
                className="rounded-lg border border-cinza/40 px-3 py-1.5 text-sm font-medium hover:bg-black/5 transition disabled:opacity-50"
              >
                Gerar novo PIN
              </button>
              {novoPin && (
                <>
                  <span className="font-mono text-lg tracking-widest text-tinta">
                    {pinVisivel ? novoPin : "••••"}
                  </span>
                  <button
                    onClick={() => setPinVisivel((v) => !v)}
                    className="rounded-lg border border-cinza/40 px-3 py-1.5 text-sm hover:bg-black/5 transition"
                  >
                    {pinVisivel ? "Ocultar" : "Revelar"}
                  </button>
                  <span className="rounded-full bg-amber-100 text-amber-800 text-xs px-2 py-0.5">
                    Não voltarás a ver este PIN — comunica-o já ao colaborador.
                  </span>
                </>
              )}
            </div>
          </div>

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

// Tab Informação — edição da ficha (recuperada do Sprint 2, commit 3a91986,
// regredida em 032097d). Guarda via RPC atualizar_colaborador (DEFINER).
function InformacaoTab({ id, onNome }: { id: string; onNome: (n: string) => void }) {
  const [pronto, setPronto] = useState(false);
  const [aGravar, setAGravar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [ativo, setAtivo] = useState(true);
  const [form, setForm] = useState({
    nome: "",
    area: "cozinha",
    nome_completo: "",
    data_nascimento: "",
    posicao: "",
    contrato_inicio: "",
    contrato_fim: "",
    telefone: "",
    email: "",
  });

  useEffect(() => {
    if (!id) return;
    (async () => {
      const { data: t, error: e1 } = await supabase
        .from("trabalhador")
        .select("nome, area, ativo")
        .eq("id", id)
        .single();
      if (e1 || !t) {
        setErro(e1?.message ?? "colaborador não encontrado");
        setPronto(true);
        return;
      }
      const { data: d, error: e2 } = await supabase
        .from("trabalhador_detalhe")
        .select("nome_completo, data_nascimento, posicao, contrato_inicio, contrato_fim, telefone, email")
        .eq("trabalhador_id", id)
        .maybeSingle();
      if (e2) setErro(e2.message);
      setAtivo(t.ativo);
      setForm({
        nome: t.nome ?? "",
        area: t.area ?? "cozinha",
        nome_completo: d?.nome_completo ?? "",
        data_nascimento: d?.data_nascimento ?? "",
        posicao: d?.posicao ?? "",
        contrato_inicio: d?.contrato_inicio ?? "",
        contrato_fim: d?.contrato_fim ?? "",
        telefone: d?.telefone ?? "",
        email: d?.email ?? "",
      });
      setPronto(true);
    })();
  }, [id]);

  function set(k: string, v: string) {
    setForm((f) => ({ ...f, [k]: v }));
  }
  // Vazio -> undefined: o parâmetro é omitido da chamada e o default SQL (null) aplica-se.
  const nn = (v: string) => (v.trim() === "" ? undefined : v.trim());

  async function gravar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setMsg(null);
    setAGravar(true);
    const { error } = await supabase.rpc("atualizar_colaborador", {
      p_id: id,
      p_nome: form.nome,
      p_area: form.area,
      p_nome_completo: nn(form.nome_completo),
      p_data_nascimento: nn(form.data_nascimento),
      p_posicao: nn(form.posicao),
      p_contrato_inicio: nn(form.contrato_inicio),
      p_contrato_fim: nn(form.contrato_fim),
      p_telefone: nn(form.telefone),
      p_email: nn(form.email),
    });
    setAGravar(false);
    if (error) return setErro(error.message);
    onNome(form.nome);
    setMsg("Guardado.");
  }

  async function alternarAtivo() {
    setErro(null);
    setMsg(null);
    const { error } = await supabase
      .from("trabalhador")
      .update({ ativo: !ativo })
      .eq("id", id);
    if (error) return setErro(error.message);
    setAtivo(!ativo);
    setMsg(!ativo ? "Reativado." : "Desativado.");
  }

  if (!pronto) return <p className="text-cinza">A carregar…</p>;

  return (
    <div className="max-w-md">
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-4 mb-4 flex items-center gap-3 flex-wrap">
        <span
          className={`rounded-full px-2 py-0.5 text-xs ${ativo ? "bg-teal/10 text-teal" : "bg-cinza/15 text-cinza"}`}
        >
          {ativo ? "ativo" : "inativo"}
        </span>
        <button
          onClick={alternarAtivo}
          className="rounded-lg border border-cinza/40 px-3 py-1.5 text-sm hover:bg-black/5 transition"
        >
          {ativo ? "Desativar" : "Reativar"}
        </button>
        <p className="text-xs text-cinza w-full">
          Um colaborador inativo deixa de conseguir picar no kiosk; o histórico mantém-se.
        </p>
      </div>

      <form
        onSubmit={gravar}
        className="space-y-4 bg-white rounded-xl border border-black/5 shadow-sm p-6"
      >
        <label className="block">
          <span className="text-sm font-medium">Nome (kiosk) *</span>
          <input
            required
            value={form.nome}
            onChange={(e) => set("nome", e.target.value)}
            className={`${inp} mt-1`}
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium">Área *</span>
          <select
            value={form.area}
            onChange={(e) => set("area", e.target.value)}
            className={`${inp} mt-1`}
          >
            {AREAS.map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="text-sm font-medium">Nome completo</span>
          <input
            value={form.nome_completo}
            onChange={(e) => set("nome_completo", e.target.value)}
            className={`${inp} mt-1`}
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium">Data de nascimento</span>
          <input
            type="date"
            value={form.data_nascimento}
            onChange={(e) => set("data_nascimento", e.target.value)}
            className={`${inp} mt-1`}
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium">Posição</span>
          <input
            value={form.posicao}
            onChange={(e) => set("posicao", e.target.value)}
            className={`${inp} mt-1`}
          />
        </label>
        <div className="flex gap-3">
          <label className="block flex-1">
            <span className="text-sm font-medium">Início contrato</span>
            <input
              type="date"
              value={form.contrato_inicio}
              onChange={(e) => set("contrato_inicio", e.target.value)}
              className={`${inp} mt-1`}
            />
          </label>
          <label className="block flex-1">
            <span className="text-sm font-medium">Fim contrato</span>
            <input
              type="date"
              value={form.contrato_fim}
              onChange={(e) => set("contrato_fim", e.target.value)}
              className={`${inp} mt-1`}
            />
          </label>
        </div>
        <label className="block">
          <span className="text-sm font-medium">Telefone</span>
          <input
            value={form.telefone}
            onChange={(e) => set("telefone", e.target.value)}
            className={`${inp} mt-1`}
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium">Email</span>
          <input
            type="email"
            value={form.email}
            onChange={(e) => set("email", e.target.value)}
            className={`${inp} mt-1`}
          />
        </label>
        {erro && <p className="text-red-600 text-sm">{erro}</p>}
        {msg && <p className="text-teal text-sm">{msg}</p>}
        <button
          type="submit"
          disabled={aGravar}
          className="rounded-lg bg-teal text-white px-5 py-2.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50"
        >
          {aGravar ? "A guardar…" : "Guardar"}
        </button>
      </form>
    </div>
  );
}
