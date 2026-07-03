"use client";
import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { supabase } from "@/lib/supabase";
import Validacoes from "./validacoes";

type Tab = "picagens" | "checklists" | "validacoes";

type Picagem = {
  picagem_id: string;
  tipo: string;
  momento_dispositivo: string;
  trabalhador_id: string;
  trabalhador_nome: string;
  codigo_pessoal: string;
  loja_nome: string;
  foto_url: string | null;
  correcao_manual: boolean;
  anulada: boolean;
};

type Recusa = {
  id: string;
  tipo: string;
  momento_dispositivo: string;
  codigo_pessoal: string | null;
  motivo: string;
  criada_em: string;
};

type Trab = { id: string; nome: string; codigo_pessoal: string };

const TIPOS = ["entrada", "saida", "inicio_intervalo", "fim_intervalo"] as const;
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
function hojeLisboa() {
  return new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Lisbon" });
}
function diasAtras(n: number) {
  const d = new Date();
  d.setDate(d.getDate() - n);
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

export default function Registos() {
  const [tab, setTab] = useState<Tab>("picagens");
  const [linhas, setLinhas] = useState<Picagem[] | null>(null);
  const [recusas, setRecusas] = useState<Recusa[]>([]);
  const [trabs, setTrabs] = useState<Trab[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [aProcessar, setAProcessar] = useState<string | null>(null);

  // filtros
  const [fColab, setFColab] = useState("todos");
  const [fTipo, setFTipo] = useState("todos");
  const [fDe, setFDe] = useState(diasAtras(7));
  const [fAte, setFAte] = useState(hojeLisboa());

  // modais
  const [modal, setModal] = useState<null | "nova" | "bloco">(null);

  const carregarPicagens = useCallback(() => {
    // Janela local de Lisboa (assume browser em Europe/Lisbon, como o resto do painel).
    const desde = new Date(`${fDe}T00:00:00`).toISOString();
    const ate = new Date(`${fAte}T23:59:59`).toISOString();
    let q = supabase
      .from("vista_picagem")
      .select(
        "picagem_id, tipo, momento_dispositivo, trabalhador_id, trabalhador_nome, codigo_pessoal, loja_nome, foto_url, correcao_manual, anulada",
      )
      .gte("momento_dispositivo", desde)
      .lte("momento_dispositivo", ate)
      .order("momento_dispositivo", { ascending: false })
      .limit(300);
    if (fColab !== "todos") q = q.eq("trabalhador_id", fColab);
    if (fTipo !== "todos") q = q.eq("tipo", fTipo);
    q.then(({ data, error }) => {
      if (error) setErro(error.message);
      else setLinhas(data as Picagem[]);
    });
  }, [fColab, fTipo, fDe, fAte]);

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
    supabase
      .from("trabalhador")
      .select("id, nome, codigo_pessoal")
      .eq("ativo", true)
      .order("nome")
      .then(({ data }) => setTrabs((data as Trab[]) ?? []));
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
          {/* Ações + filtros */}
          <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
            <div className="flex flex-wrap items-end gap-3">
              <div>
                <label className="block text-xs text-cinza mb-1">Colaborador</label>
                <select
                  value={fColab}
                  onChange={(e) => setFColab(e.target.value)}
                  className="rounded-lg border border-black/15 px-3 py-1.5 text-sm bg-white"
                >
                  <option value="todos">Todos</option>
                  {trabs.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.nome} ({t.codigo_pessoal})
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs text-cinza mb-1">Tipo</label>
                <select
                  value={fTipo}
                  onChange={(e) => setFTipo(e.target.value)}
                  className="rounded-lg border border-black/15 px-3 py-1.5 text-sm bg-white"
                >
                  <option value="todos">Todos</option>
                  {TIPOS.map((t) => (
                    <option key={t} value={t}>
                      {TIPO_LABEL[t]}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs text-cinza mb-1">De</label>
                <input
                  type="date"
                  value={fDe}
                  onChange={(e) => setFDe(e.target.value)}
                  className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
                />
              </div>
              <div>
                <label className="block text-xs text-cinza mb-1">Até</label>
                <input
                  type="date"
                  value={fAte}
                  onChange={(e) => setFAte(e.target.value)}
                  className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
                />
              </div>
            </div>

            <div className="flex gap-2">
              <button
                onClick={() => setModal("bloco")}
                className="rounded-lg border border-teal text-teal px-4 py-1.5 text-sm font-medium hover:bg-teal/5 transition"
              >
                Picagens em bloco
              </button>
              <button
                onClick={() => setModal("nova")}
                className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition"
              >
                Nova picagem
              </button>
            </div>
          </div>

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
                    <th className="px-4 py-3 font-medium">Origem</th>
                  </tr>
                </thead>
                <tbody>
                  {linhas.map((l) => (
                    <tr
                      key={l.picagem_id}
                      className={`border-b border-black/5 last:border-0 hover:bg-papel/50 ${
                        l.anulada ? "opacity-50" : ""
                      }`}
                    >
                      <td className="px-4 py-3">
                        <span className={l.anulada ? "line-through" : ""}>
                          {fmt(l.momento_dispositivo)}
                        </span>
                        {l.anulada && (
                          <span className="ml-2 rounded-full bg-cinza/15 text-cinza text-xs px-2 py-0.5">
                            anulada
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        {l.trabalhador_nome}{" "}
                        <span className="text-cinza">({l.codigo_pessoal})</span>
                      </td>
                      <td className="px-4 py-3 text-cinza">{l.loja_nome}</td>
                      <td className="px-4 py-3">{TIPO_LABEL[l.tipo] ?? l.tipo}</td>
                      <td className="px-4 py-3">
                        {l.correcao_manual ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-100 text-amber-800 text-xs px-2 py-0.5">
                            Manual
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-teal/10 text-teal text-xs px-2 py-0.5">
                            Dispositivo
                          </span>
                        )}
                        {l.foto_url && (
                          <button
                            onClick={() => verFoto(l.foto_url as string)}
                            className="ml-2 text-teal hover:underline text-xs"
                          >
                            ver foto
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                  {linhas.length === 0 && (
                    <tr>
                      <td colSpan={5} className="px-4 py-6 text-cinza">
                        Sem picagens no período.
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

      {tab === "validacoes" && <Validacoes />}

      {modal === "nova" && (
        <NovaPicagemModal
          trabs={trabs}
          onClose={() => setModal(null)}
          onDone={() => {
            setModal(null);
            carregarPicagens();
          }}
        />
      )}
      {modal === "bloco" && (
        <BlocoModal
          trabs={trabs}
          onClose={() => setModal(null)}
          onDone={() => {
            carregarPicagens();
          }}
        />
      )}
    </div>
  );
}

/* ---------------------------------------------------------------- Modal base */

function Modal({
  titulo,
  onClose,
  children,
  max = "max-w-lg",
}: {
  titulo: string;
  onClose: () => void;
  children: ReactNode;
  max?: string;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-auto bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className={`mt-10 w-full ${max} rounded-2xl bg-white shadow-xl`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-black/10 px-5 py-4">
          <h2 className="text-lg font-bold text-tinta">{titulo}</h2>
          <button
            onClick={onClose}
            className="text-cinza hover:text-tinta text-xl leading-none"
            aria-label="Fechar"
          >
            ✕
          </button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

/* --------------------------------------------------------- Nova picagem (unitária) */

function NovaPicagemModal({
  trabs,
  onClose,
  onDone,
}: {
  trabs: Trab[];
  onClose: () => void;
  onDone: () => void;
}) {
  const [colab, setColab] = useState("");
  const [tipo, setTipo] = useState<string>("entrada");
  const [momento, setMomento] = useState(""); // datetime-local
  const [busy, setBusy] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function guardar() {
    setErro(null);
    if (!colab) return setErro("Escolhe o colaborador.");
    if (!momento) return setErro("Indica a data e a hora.");
    setBusy(true);
    // datetime-local é hora de parede; assume-se browser em Europe/Lisbon (como o resto do painel).
    const iso = new Date(momento).toISOString();
    const { error } = await supabase.rpc("corrigir_picagem", {
      p_trabalhador_id: colab,
      p_tipo: tipo,
      p_momento: iso,
      p_motivo: "manual",
    });
    setBusy(false);
    if (error) return setErro(error.message);
    onDone();
  }

  return (
    <Modal titulo="Nova picagem" onClose={onClose}>
      <div className="space-y-4">
        <p className="text-sm text-cinza">
          Cria uma picagem manual (sem foto, atribuída a ti como correção). Fica marcada
          como <strong>Manual</strong> na lista.
        </p>
        <div>
          <label className="block text-xs text-cinza mb-1">Colaborador</label>
          <select
            value={colab}
            onChange={(e) => setColab(e.target.value)}
            className="w-full rounded-lg border border-black/15 px-3 py-2 text-sm bg-white"
          >
            <option value="">Escolher…</option>
            {trabs.map((t) => (
              <option key={t.id} value={t.id}>
                {t.nome} ({t.codigo_pessoal})
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs text-cinza mb-1">Tipo de movimento</label>
          <select
            value={tipo}
            onChange={(e) => setTipo(e.target.value)}
            className="w-full rounded-lg border border-black/15 px-3 py-2 text-sm bg-white"
          >
            {TIPOS.map((t) => (
              <option key={t} value={t}>
                {TIPO_LABEL[t]}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs text-cinza mb-1">Data e hora</label>
          <input
            type="datetime-local"
            value={momento}
            onChange={(e) => setMomento(e.target.value)}
            className="w-full rounded-lg border border-black/15 px-3 py-2 text-sm"
          />
        </div>

        {erro && <p className="text-sm text-red-600">{erro}</p>}

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="rounded-lg border border-black/15 text-tinta px-4 py-1.5 text-sm font-medium hover:bg-papel transition"
          >
            Cancelar
          </button>
          <button
            onClick={guardar}
            disabled={busy}
            className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50"
          >
            Guardar
          </button>
        </div>
      </div>
    </Modal>
  );
}

/* --------------------------------------------------------- Picagens em bloco */

type Movimento = { tipo: string; hora: string };
type ResBloco = {
  simulado: boolean;
  planeadas: number;
  aplicadas: number;
  ignoradas: { trabalhador: string; nome: string; data: string; motivo: string }[];
  erros: { trabalhador?: string; nome?: string; data?: string; erro: string }[];
  detalhes: { trabalhador: string; nome: string; data: string; tipo: string; hora: string }[];
};

function BlocoModal({
  trabs,
  onClose,
  onDone,
}: {
  trabs: Trab[];
  onClose: () => void;
  onDone: () => void;
}) {
  const [de, setDe] = useState(hojeLisboa());
  const [ate, setAte] = useState(hojeLisboa());
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [movs, setMovs] = useState<Movimento[]>([{ tipo: "entrada", hora: "" }]);
  const [preview, setPreview] = useState<ResBloco | null>(null);
  const [feito, setFeito] = useState<ResBloco | null>(null);
  const [busy, setBusy] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const datas = useMemo(() => (de <= ate ? diasEntre(de, ate) : []), [de, ate]);

  function toggle(id: string) {
    setSel((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
    setPreview(null);
  }
  function todos() {
    setSel(new Set(trabs.map((t) => t.id)));
    setPreview(null);
  }
  function nenhum() {
    setSel(new Set());
    setPreview(null);
  }
  function setMov(i: number, campo: keyof Movimento, v: string) {
    setMovs((m) => m.map((x, j) => (j === i ? { ...x, [campo]: v } : x)));
    setPreview(null);
  }
  function addMov() {
    setMovs((m) => [...m, { tipo: "saida", hora: "" }]);
    setPreview(null);
  }
  function rmMov(i: number) {
    setMovs((m) => (m.length === 1 ? m : m.filter((_, j) => j !== i)));
    setPreview(null);
  }

  function validar(): string | null {
    if (datas.length === 0) return "O intervalo de datas é inválido.";
    if (sel.size === 0) return "Escolhe pelo menos um colaborador.";
    for (const m of movs) {
      if (!/^\d{2}:\d{2}$/.test(m.hora)) return "Preenche todas as horas (HH:MM).";
    }
    return null;
  }

  async function correr(simular: boolean) {
    const v = validar();
    if (v) return setErro(v);
    setErro(null);
    setBusy(true);
    const { data, error } = await supabase.rpc("corrigir_picagem_bloco", {
      p_datas: datas,
      p_trabalhadores: Array.from(sel),
      p_movimentos: movs,
      p_simular: simular,
    });
    setBusy(false);
    if (error) return setErro(error.message);
    if (simular) setPreview(data as ResBloco);
    else {
      setFeito(data as ResBloco);
      setPreview(null);
      onDone();
    }
  }

  const totalPicagens = datas.length * sel.size * movs.length;

  return (
    <Modal titulo="Picagens em bloco" onClose={onClose} max="max-w-2xl">
      {feito ? (
        <div className="space-y-3">
          <p className="text-sm font-medium text-teal">
            Aplicadas {feito.aplicadas} picagem(ns).
          </p>
          <RelatorioBloco res={feito} />
          <div className="flex justify-end">
            <button
              onClick={onClose}
              className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition"
            >
              Fechar
            </button>
          </div>
        </div>
      ) : (
        <div className="space-y-5">
          <p className="text-sm text-cinza">
            Aplica os mesmos movimentos a vários colaboradores e dias. Cada picagem fica
            marcada como <strong>Manual</strong>. Antes de aplicar, simula: dias com sequência
            inválida (ex.: já há uma entrada nesse dia) são <strong>ignorados</strong> e listados.
          </p>

          {/* Datas */}
          <div className="flex flex-wrap items-end gap-3">
            <div>
              <label className="block text-xs text-cinza mb-1">De</label>
              <input
                type="date"
                value={de}
                onChange={(e) => {
                  setDe(e.target.value);
                  setPreview(null);
                }}
                className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
              />
            </div>
            <div>
              <label className="block text-xs text-cinza mb-1">Até</label>
              <input
                type="date"
                value={ate}
                onChange={(e) => {
                  setAte(e.target.value);
                  setPreview(null);
                }}
                className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
              />
            </div>
            <p className="text-xs text-cinza pb-2">
              {datas.length > 0 ? `${datas.length} dia(s)` : "intervalo inválido"}
            </p>
          </div>

          {/* Colaboradores */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="block text-xs text-cinza">
                Colaboradores ({sel.size} de {trabs.length})
              </label>
              <div className="flex gap-2 text-xs">
                <button onClick={todos} className="text-teal hover:underline">
                  Todos
                </button>
                <button onClick={nenhum} className="text-cinza hover:underline">
                  Nenhum
                </button>
              </div>
            </div>
            <div className="max-h-40 overflow-auto rounded-lg border border-black/15 divide-y divide-black/5">
              {trabs.map((t) => (
                <label
                  key={t.id}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm hover:bg-papel/50 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    checked={sel.has(t.id)}
                    onChange={() => toggle(t.id)}
                    className="accent-teal"
                  />
                  <span className="text-tinta">{t.nome}</span>
                  <span className="text-cinza">({t.codigo_pessoal})</span>
                </label>
              ))}
            </div>
          </div>

          {/* Movimentos */}
          <div>
            <label className="block text-xs text-cinza mb-1">Movimentos</label>
            <div className="space-y-2">
              {movs.map((m, i) => (
                <div key={i} className="flex items-center gap-2">
                  <select
                    value={m.tipo}
                    onChange={(e) => setMov(i, "tipo", e.target.value)}
                    className="rounded-lg border border-black/15 px-3 py-1.5 text-sm bg-white"
                  >
                    {TIPOS.map((t) => (
                      <option key={t} value={t}>
                        {TIPO_LABEL[t]}
                      </option>
                    ))}
                  </select>
                  <input
                    type="time"
                    value={m.hora}
                    onChange={(e) => setMov(i, "hora", e.target.value)}
                    className="rounded-lg border border-black/15 px-3 py-1.5 text-sm"
                  />
                  <button
                    onClick={() => rmMov(i)}
                    disabled={movs.length === 1}
                    className="rounded-lg border border-black/15 text-cinza px-2.5 py-1.5 text-sm hover:bg-papel transition disabled:opacity-40"
                    aria-label="Remover movimento"
                  >
                    −
                  </button>
                </div>
              ))}
            </div>
            <button
              onClick={addMov}
              className="mt-2 rounded-lg border border-teal text-teal px-3 py-1 text-sm font-medium hover:bg-teal/5 transition"
            >
              + Movimento
            </button>
          </div>

          {erro && <p className="text-sm text-red-600">{erro}</p>}

          {/* Pré-visualização */}
          {preview && <RelatorioBloco res={preview} />}

          <div className="flex items-center justify-between gap-2 pt-1">
            <p className="text-xs text-cinza">
              {totalPicagens > 0 && `Até ${totalPicagens} picagem(ns) (antes do pré-flight)`}
            </p>
            <div className="flex gap-2">
              <button
                onClick={onClose}
                className="rounded-lg border border-black/15 text-tinta px-4 py-1.5 text-sm font-medium hover:bg-papel transition"
              >
                Cancelar
              </button>
              <button
                onClick={() => correr(true)}
                disabled={busy}
                className="rounded-lg border border-teal text-teal px-4 py-1.5 text-sm font-medium hover:bg-teal/5 transition disabled:opacity-50"
              >
                Simular
              </button>
              <button
                onClick={() => correr(false)}
                disabled={busy || !preview || preview.planeadas === 0}
                className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50"
                title={!preview ? "Simula primeiro" : ""}
              >
                Aplicar
              </button>
            </div>
          </div>
        </div>
      )}
    </Modal>
  );
}

function RelatorioBloco({ res }: { res: ResBloco }) {
  return (
    <div className="rounded-lg border border-black/10 bg-papel/40 p-4 space-y-2">
      <p className="text-sm font-medium text-tinta">
        {res.simulado
          ? res.planeadas === 0
            ? "Nada a aplicar."
            : `${res.planeadas} picagem(ns) a aplicar.`
          : `${res.aplicadas} aplicada(s).`}
      </p>

      {res.ignoradas.length > 0 && (
        <div className="text-sm text-amber-800">
          <p className="font-medium">{res.ignoradas.length} dia(s) ignorado(s):</p>
          <ul className="list-disc pl-5">
            {res.ignoradas.map((g, i) => (
              <li key={i}>
                {g.nome} · {g.data} — {g.motivo}
              </li>
            ))}
          </ul>
        </div>
      )}

      {res.erros.length > 0 && (
        <div className="text-sm text-red-700">
          <p className="font-medium">{res.erros.length} erro(s):</p>
          <ul className="list-disc pl-5">
            {res.erros.map((e, i) => (
              <li key={i}>
                {e.nome ? `${e.nome} · ` : ""}
                {e.data ? `${e.data} — ` : ""}
                {e.erro}
              </li>
            ))}
          </ul>
        </div>
      )}

      {res.detalhes.length > 0 && (
        <div className="max-h-40 overflow-auto rounded border border-black/5 bg-white">
          <table className="w-full text-xs">
            <tbody>
              {res.detalhes.map((d, i) => (
                <tr key={i} className="border-b border-black/5 last:border-0">
                  <td className="px-2 py-1 text-cinza">{d.nome}</td>
                  <td className="px-2 py-1">{d.data}</td>
                  <td className="px-2 py-1">{TIPO_LABEL[d.tipo] ?? d.tipo}</td>
                  <td className="px-2 py-1 text-teal">+ {d.hora}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

/* ----------------------------------------------------------------- Placeholder */

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
