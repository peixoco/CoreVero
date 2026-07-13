"use client";
import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { ErroAviso, mensagemErro } from "@/lib/erros";
import type { Json } from "@corevero/core";

/* ================================================================== Tipos */

type Template = {
  id: string;
  nome: string;
  ativo: boolean;
  loja_id: string | null;
  loja: { nome: string } | null;
};

type Versao = {
  id: string;
  numero: number;
  estado: string;
  frequencia_tipo: string;
  frequencia_config: Record<string, unknown>;
  publicada_em: string | null;
};

type Item = {
  id: string;
  empresa_id: string;
  versao_id: string;
  ordem: number;
  texto: string;
  tipo_resposta: string;
  unidade: string | null;
  limite_min: number | null;
  limite_max: number | null;
  booleano_conforme: boolean | null;
  obrigatorio: boolean;
  limite_fonte: string | null;
  limite_referencia: string | null;
  limite_legal_id: string | null;
};

type ItemUpdate = Partial<Omit<Item, "id" | "empresa_id" | "versao_id">>;

type LimiteLegal = {
  id: string;
  controlo: string;
  descricao: string;
  norma: string;
  unidade: string;
  limite_min: number | null;
  limite_max: number | null;
};

type FreqConfigDiaria = { vezes_por_dia: number; janelas: string[] };
type FreqConfigSemanal = { dia_semana: number };

type RelatorioPublicacao = {
  versao_id: string;
  template_id: string;
  numero: number;
  itens: number;
  versao_arquivada: string | null;
};

/* =============================================================== Constantes */

const DIAS_SEMANA = [
  { valor: 1, label: "Segunda-feira" },
  { valor: 2, label: "Terça-feira" },
  { valor: 3, label: "Quarta-feira" },
  { valor: 4, label: "Quinta-feira" },
  { valor: 5, label: "Sexta-feira" },
  { valor: 6, label: "Sábado" },
  { valor: 7, label: "Domingo" },
];

const TIPO_RESPOSTA_LABEL: Record<string, string> = {
  numerico: "Numérico",
  booleano: "Booleano (Sim/Não)",
  texto: "Texto livre",
  foto: "Fotografia",
};

const LIMITE_FONTE_LABEL: Record<string, string> = {
  lei: "Lei",
  codigo_boas_praticas: "Código de boas práticas",
  plano_estabelecimento: "Plano do estabelecimento",
};

const inp =
  "w-full rounded-lg border border-black/15 bg-white px-3 py-2 text-sm outline-none focus:border-teal focus:ring-2 focus:ring-teal/20";
const inpSm =
  "rounded-lg border border-black/15 bg-white px-2 py-1.5 text-sm outline-none focus:border-teal focus:ring-2 focus:ring-teal/20";

/* ================================================================ Helpers */

function fmt(ts: string) {
  return new Date(ts).toLocaleDateString("pt-PT", {
    dateStyle: "short",
    timeZone: "Europe/Lisbon",
  });
}

/**
 * Validação visual de um item contra o limite estatutário.
 * Replica o critério da RPC publicar_versao para dar feedback antecipado.
 *
 * - "mais exigente" (max menor, min maior): aviso amarelo, permitido.
 * - "menos exigente" (max maior/ausente quando estatutário tem max,
 *    min menor/ausente quando estatutário tem min, unidade diferente):
 *    erro vermelho, bloqueia publicação.
 */
function validarContraLegal(
  item: Item,
  limitesLegais: LimiteLegal[],
): { aviso: string | null; erro: string | null } {
  if (item.tipo_resposta !== "numerico" || !item.limite_legal_id) {
    return { aviso: null, erro: null };
  }
  const legal = limitesLegais.find((l) => l.id === item.limite_legal_id);
  if (!legal) return { aviso: null, erro: null };

  const erros: string[] = [];
  const avisos: string[] = [];

  if (item.unidade !== legal.unidade) {
    erros.push(`Unidade "${item.unidade ?? "—"}" difere da estatutária ("${legal.unidade}")`);
  }

  if (legal.limite_max !== null) {
    if (item.limite_max === null) {
      erros.push(
        `Limite máximo em falta (estatutário: ≤${legal.limite_max} ${legal.unidade})`,
      );
    } else if (item.limite_max > legal.limite_max) {
      erros.push(
        `Limite máximo ${item.limite_max} é mais permissivo que o estatutário (≤${legal.limite_max})`,
      );
    } else if (item.limite_max < legal.limite_max) {
      avisos.push(
        `Limite máximo ${item.limite_max} é mais exigente que o estatutário (≤${legal.limite_max})`,
      );
    }
  }

  if (legal.limite_min !== null) {
    if (item.limite_min === null) {
      erros.push(
        `Limite mínimo em falta (estatutário: ≥${legal.limite_min} ${legal.unidade})`,
      );
    } else if (item.limite_min < legal.limite_min) {
      erros.push(
        `Limite mínimo ${item.limite_min} é mais permissivo que o estatutário (≥${legal.limite_min})`,
      );
    } else if (item.limite_min > legal.limite_min) {
      avisos.push(
        `Limite mínimo ${item.limite_min} é mais exigente que o estatutário (≥${legal.limite_min})`,
      );
    }
  }

  return {
    aviso: avisos.length > 0 ? avisos.join("; ") : null,
    erro: erros.length > 0 ? erros.join("; ") : null,
  };
}

/* ============================================================= Componente principal */

export default function ChecklistDetalhe() {
  const { id } = useParams<{ id: string }>();

  const [template, setTemplate] = useState<Template | null>(null);
  const [versoes, setVersoes] = useState<Versao[]>([]);
  const [itens, setItens] = useState<Item[]>([]);
  const [limitesLegais, setLimitesLegais] = useState<LimiteLegal[]>([]);
  const [empresaId, setEmpresaId] = useState<string | null>(null);

  const [loading, setLoading] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Estado da frequência (editado localmente, guardado explicitamente)
  const [freqTipo, setFreqTipo] = useState<string>("diaria");
  const [freqConfig, setFreqConfig] = useState<Record<string, unknown>>({
    vezes_por_dia: 1,
    janelas: ["08:00"],
  });
  const [freqDirty, setFreqDirty] = useState(false);

  // Estado da publicação
  const [erroPublicacao, setErroPublicacao] = useState<string | null>(null);
  const [relatorioPublicacao, setRelatorioPublicacao] =
    useState<RelatorioPublicacao | null>(null);

  // Versões derivadas
  const rascunho = versoes.find((v) => v.estado === "rascunho") ?? null;
  const publicada = versoes.find((v) => v.estado === "publicada") ?? null;

  // Há algum item com erro de conformidade legal?
  const temErroLegal = itens.some(
    (item) => validarContraLegal(item, limitesLegais).erro !== null,
  );

  /* ---------------------------------------------------------- Carregamento */

  const carregarItens = useCallback(async (versaoId: string) => {
    const { data, error } = await supabase
      .from("checklist_item")
      .select("*")
      .eq("versao_id", versaoId)
      .order("ordem");
    if (error) setErro(mensagemErro(error));
    else setItens((data as Item[]) ?? []);
  }, []);

  const carregarTudo = useCallback(async () => {
    setLoading(true);
    setErro(null);

    const [empRes, templRes, versoesRes, limRes] = await Promise.all([
      supabase.rpc("empresa_atual"),
      supabase
        .from("checklist_template")
        // FK composta: embed pelo nome da constraint (ver lista)
        .select("id, nome, ativo, loja_id, loja:checklist_template_empresa_id_loja_id_fkey(nome)")
        .eq("id", id)
        .single(),
      supabase
        .from("checklist_template_versao")
        .select("id, numero, estado, frequencia_tipo, frequencia_config, publicada_em")
        .eq("template_id", id)
        .order("numero", { ascending: false }),
      supabase.from("limite_legal").select("*"),
    ]);

    if (empRes.error) {
      setErro(mensagemErro(empRes.error));
      setLoading(false);
      return;
    }
    if (templRes.error) {
      setErro(mensagemErro(templRes.error));
      setLoading(false);
      return;
    }
    if (versoesRes.error) {
      setErro(mensagemErro(versoesRes.error));
      setLoading(false);
      return;
    }
    if (limRes.error) {
      setErro(mensagemErro(limRes.error));
      setLoading(false);
      return;
    }

    const novasVersoes = (versoesRes.data as unknown as Versao[]) ?? [];
    const rascunhoNovo = novasVersoes.find((v) => v.estado === "rascunho") ?? null;
    const publicadaNova = novasVersoes.find((v) => v.estado === "publicada") ?? null;

    setEmpresaId(empRes.data as string);
    setTemplate(templRes.data as unknown as Template);
    setVersoes(novasVersoes);
    setLimitesLegais((limRes.data as LimiteLegal[]) ?? []);

    // Inicializar frequência do rascunho
    if (rascunhoNovo) {
      setFreqTipo(rascunhoNovo.frequencia_tipo);
      setFreqConfig(rascunhoNovo.frequencia_config as Record<string, unknown>);
      setFreqDirty(false);
    }

    // Carregar itens da versão mais relevante (rascunho > publicada)
    const versaoAlvo = rascunhoNovo ?? publicadaNova;
    if (versaoAlvo) {
      await carregarItens(versaoAlvo.id);
    } else {
      setItens([]);
    }

    setLoading(false);
  }, [id, carregarItens]);

  useEffect(() => {
    carregarTudo();
  }, [carregarTudo]);

  /* ----------------------------------------- Operações sobre o template */

  async function guardarNome(novoNome: string) {
    const trimado = novoNome.trim();
    if (!template || !trimado || trimado === template.nome) return;
    const { error } = await supabase
      .from("checklist_template")
      .update({ nome: trimado })
      .eq("id", id);
    if (error) setErro(mensagemErro(error));
    else setTemplate((t) => (t ? { ...t, nome: trimado } : t));
  }

  async function toggleAtivo() {
    if (!template) return;
    const novoAtivo = !template.ativo;
    const { error } = await supabase
      .from("checklist_template")
      .update({ ativo: novoAtivo })
      .eq("id", id);
    if (error) setErro(mensagemErro(error));
    else setTemplate((t) => (t ? { ...t, ativo: novoAtivo } : t));
  }

  /* ---------------------------------------- Operações sobre a frequência */

  async function guardarFrequencia() {
    if (!rascunho) return;
    // Só atualizar as colunas permitidas pelo grant; cast Json para satisfazer os tipos gerados
    const { error } = await supabase
      .from("checklist_template_versao")
      .update({ frequencia_tipo: freqTipo, frequencia_config: freqConfig as unknown as Json })
      .eq("id", rascunho.id);
    if (error) {
      setErro(mensagemErro(error));
    } else {
      setFreqDirty(false);
      setVersoes((vs) =>
        vs.map((v) =>
          v.id === rascunho.id
            ? { ...v, frequencia_tipo: freqTipo, frequencia_config: freqConfig }
            : v,
        ),
      );
    }
  }

  /* -------------------------------------------- Operações sobre os itens */

  async function guardarItemCampos(
    itemId: string,
    campos: ItemUpdate,
    rascunhoId: string | undefined,
  ) {
    const { error } = await supabase
      .from("checklist_item")
      .update(campos)
      .eq("id", itemId);
    if (error) {
      setErro(mensagemErro(error));
      if (rascunhoId) carregarItens(rascunhoId);
    }
  }

  function atualizarItem(itemId: string, campos: ItemUpdate) {
    // Atualização otimista + persistência
    setItens((prev) =>
      prev.map((i) => (i.id === itemId ? { ...i, ...campos } : i)),
    );
    guardarItemCampos(itemId, campos, rascunho?.id);
  }

  function ligarLimiteLegal(item: Item, legalId: string | null) {
    if (!legalId) {
      atualizarItem(item.id, { limite_legal_id: null });
      return;
    }
    const legal = limitesLegais.find((l) => l.id === legalId);
    if (!legal) return;
    // Pré-preencher campos estatutários
    atualizarItem(item.id, {
      limite_legal_id: legalId,
      unidade: legal.unidade,
      limite_min: legal.limite_min,
      limite_max: legal.limite_max,
      limite_fonte: "lei",
      limite_referencia: legal.norma,
    });
  }

  async function moverItem(itemId: string, direcao: "cima" | "baixo") {
    const idx = itens.findIndex((i) => i.id === itemId);
    if (idx < 0) return;
    const outroIdx = direcao === "cima" ? idx - 1 : idx + 1;
    if (outroIdx < 0 || outroIdx >= itens.length) return;

    const item = itens[idx];
    const outro = itens[outroIdx];
    const ordemItem = outro.ordem;
    const ordemOutro = item.ordem;

    // Atualização otimista
    const novosItens = itens.map((i) => {
      if (i.id === item.id) return { ...i, ordem: ordemItem };
      if (i.id === outro.id) return { ...i, ordem: ordemOutro };
      return i;
    });
    novosItens.sort((a, b) => a.ordem - b.ordem);
    setItens(novosItens);

    // Persistir os dois swaps
    const [r1, r2] = await Promise.all([
      supabase
        .from("checklist_item")
        .update({ ordem: ordemItem })
        .eq("id", item.id),
      supabase
        .from("checklist_item")
        .update({ ordem: ordemOutro })
        .eq("id", outro.id),
    ]);
    const erroPersistencia = r1.error ?? r2.error;
    if (erroPersistencia) {
      setErro(mensagemErro(erroPersistencia));
      if (rascunho) carregarItens(rascunho.id);
    }
  }

  async function adicionarItem() {
    if (!rascunho || !empresaId) return;
    const maxOrdem = itens.reduce((m, i) => Math.max(m, i.ordem), 0);
    const { data, error } = await supabase
      .from("checklist_item")
      .insert({
        empresa_id: empresaId,
        versao_id: rascunho.id,
        ordem: maxOrdem + 1,
        texto: "Novo ponto de controlo",
        tipo_resposta: "booleano",
        obrigatorio: true,
      })
      .select("*")
      .single();
    if (error) setErro(mensagemErro(error));
    else setItens((prev) => [...prev, data as Item]);
  }

  async function removerItem(itemId: string) {
    if (!window.confirm("Remover este item? A ação não pode ser desfeita.")) return;
    const { error } = await supabase
      .from("checklist_item")
      .delete()
      .eq("id", itemId);
    if (error) setErro(mensagemErro(error));
    else setItens((prev) => prev.filter((i) => i.id !== itemId));
  }

  /* ---------------------------------------- Operações sobre as versões */

  async function publicar() {
    if (!rascunho) return;
    setErroPublicacao(null);
    setRelatorioPublicacao(null);
    setBusy(true);
    const { data, error } = await supabase.rpc("publicar_versao", {
      p_versao_id: rascunho.id,
    });
    setBusy(false);
    if (error) {
      setErroPublicacao(mensagemErro(error));
    } else {
      setRelatorioPublicacao(data as RelatorioPublicacao);
      await carregarTudo();
    }
  }

  async function apagarRascunho() {
    if (!rascunho) return;
    if (
      !window.confirm(
        "Apagar este rascunho e todos os seus itens? A ação não pode ser desfeita.",
      )
    )
      return;
    setBusy(true);
    const { error } = await supabase
      .from("checklist_template_versao")
      .delete()
      .eq("id", rascunho.id);
    setBusy(false);
    if (error) setErro(mensagemErro(error));
    else await carregarTudo();
  }

  async function criarRascunho(versaoId: string) {
    setBusy(true);
    const { error } = await supabase.rpc("criar_rascunho_de", {
      p_versao_id: versaoId,
    });
    setBusy(false);
    if (error) setErro(mensagemErro(error));
    else await carregarTudo();
  }

  /* -------------------------------------------------------------- Render */

  if (loading) {
    return <p className="text-cinza">A carregar…</p>;
  }

  if (!template) {
    return (
      <div>
        <ErroAviso erro={erro} />
        <p className="text-cinza mt-4">Template não encontrado.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Fio de migalhas */}
      <nav className="flex items-center gap-2 text-sm text-cinza">
        <Link href="/checklists" className="hover:text-tinta">
          Checklists
        </Link>
        <span>/</span>
        <span className="text-tinta">{template.nome}</span>
      </nav>

      <ErroAviso erro={erro} className="mb-2" />

      {/* Cabeçalho do template */}
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-6">
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1 min-w-0">
            <input
              type="text"
              defaultValue={template.nome}
              onBlur={(e) => guardarNome(e.target.value)}
              className="text-2xl font-bold border-b-2 border-transparent focus:border-teal outline-none bg-transparent w-full"
              aria-label="Nome do template"
            />
            <p className="text-sm text-cinza mt-1">
              Âmbito:{" "}
              <span className="font-medium">
                {template.loja ? template.loja.nome : "Empresa"}
              </span>
            </p>
          </div>
          <label className="flex items-center gap-2 cursor-pointer select-none shrink-0">
            <input
              type="checkbox"
              checked={template.ativo}
              onChange={toggleAtivo}
              className="accent-teal w-4 h-4"
            />
            <span className="text-sm font-medium">Ativo</span>
          </label>
        </div>
      </div>

      {/* Editor ou vista */}
      {rascunho ? (
        <EditorRascunho
          rascunho={rascunho}
          itens={itens}
          limitesLegais={limitesLegais}
          freqTipo={freqTipo}
          freqConfig={freqConfig}
          freqDirty={freqDirty}
          temErroLegal={temErroLegal}
          busy={busy}
          erroPublicacao={erroPublicacao}
          relatorioPublicacao={relatorioPublicacao}
          onFreqTipoChange={(tipo) => {
            setFreqTipo(tipo);
            let cfg: Record<string, unknown> = {};
            if (tipo === "diaria") cfg = { vezes_por_dia: 1, janelas: ["08:00"] };
            if (tipo === "semanal") cfg = { dia_semana: 1 };
            setFreqConfig(cfg);
            setFreqDirty(true);
          }}
          onFreqConfigChange={(cfg) => {
            setFreqConfig(cfg);
            setFreqDirty(true);
          }}
          onGuardarFreq={guardarFrequencia}
          onAtualizarItem={atualizarItem}
          onLigarLimiteLegal={ligarLimiteLegal}
          onMoverItem={moverItem}
          onAdicionarItem={adicionarItem}
          onRemoverItem={removerItem}
          onPublicar={publicar}
          onApagarRascunho={apagarRascunho}
        />
      ) : publicada ? (
        <VistaPublicada
          publicada={publicada}
          itens={itens}
          limitesLegais={limitesLegais}
          busy={busy}
          onCriarRascunho={() => criarRascunho(publicada.id)}
        />
      ) : (
        <div className="rounded-xl border border-dashed border-black/15 bg-papel/40 p-8 text-center">
          <p className="text-cinza text-sm">
            Sem versões. Usa o histórico abaixo para criar um rascunho.
          </p>
        </div>
      )}

      {/* Histórico de versões */}
      {versoes.length > 0 && (
        <div>
          <h2 className="text-lg font-semibold mb-3">Histórico de versões</h2>
          <div className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-cinza border-b border-black/5">
                  <th className="px-4 py-3 font-medium">Versão</th>
                  <th className="px-4 py-3 font-medium">Estado</th>
                  <th className="px-4 py-3 font-medium">Publicada em</th>
                  <th className="px-4 py-3 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {versoes.map((v) => (
                  <tr key={v.id} className="border-b border-black/5 last:border-0">
                    <td className="px-4 py-3 font-medium">v.{v.numero}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs ${
                          v.estado === "publicada"
                            ? "bg-teal/10 text-teal"
                            : v.estado === "rascunho"
                              ? "bg-amber-100 text-amber-700"
                              : "bg-cinza/15 text-cinza"
                        }`}
                      >
                        {v.estado}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-cinza">
                      {v.publicada_em ? fmt(v.publicada_em) : "—"}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {v.estado !== "rascunho" && !rascunho && (
                        <button
                          onClick={() => criarRascunho(v.id)}
                          disabled={busy}
                          className="text-teal hover:underline text-xs font-medium disabled:opacity-50"
                        >
                          Criar rascunho a partir desta versão
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

/* ========================================================= EditorRascunho */

function EditorRascunho({
  rascunho,
  itens,
  limitesLegais,
  freqTipo,
  freqConfig,
  freqDirty,
  temErroLegal,
  busy,
  erroPublicacao,
  relatorioPublicacao,
  onFreqTipoChange,
  onFreqConfigChange,
  onGuardarFreq,
  onAtualizarItem,
  onLigarLimiteLegal,
  onMoverItem,
  onAdicionarItem,
  onRemoverItem,
  onPublicar,
  onApagarRascunho,
}: {
  rascunho: Versao;
  itens: Item[];
  limitesLegais: LimiteLegal[];
  freqTipo: string;
  freqConfig: Record<string, unknown>;
  freqDirty: boolean;
  temErroLegal: boolean;
  busy: boolean;
  erroPublicacao: string | null;
  relatorioPublicacao: RelatorioPublicacao | null;
  onFreqTipoChange: (tipo: string) => void;
  onFreqConfigChange: (cfg: Record<string, unknown>) => void;
  onGuardarFreq: () => void;
  onAtualizarItem: (id: string, campos: ItemUpdate) => void;
  onLigarLimiteLegal: (item: Item, legalId: string | null) => void;
  onMoverItem: (id: string, dir: "cima" | "baixo") => void;
  onAdicionarItem: () => void;
  onRemoverItem: (id: string) => void;
  onPublicar: () => void;
  onApagarRascunho: () => void;
}) {
  const freqDiaria = freqConfig as unknown as FreqConfigDiaria;
  const freqSemanal = freqConfig as unknown as FreqConfigSemanal;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <h2 className="text-lg font-semibold">Rascunho v.{rascunho.numero}</h2>
        <span className="rounded-full bg-amber-100 text-amber-700 text-xs px-2 py-0.5">
          em edição
        </span>
      </div>

      {/* --- Frequência --- */}
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-5">
        <h3 className="font-medium mb-4">Frequência de verificação</h3>
        <div className="space-y-3">
          <div>
            <label className="block text-xs text-cinza mb-1">
              Tipo de frequência
            </label>
            <select
              value={freqTipo}
              onChange={(e) => onFreqTipoChange(e.target.value)}
              className={inpSm + " w-56"}
            >
              <option value="diaria">Diária</option>
              <option value="por_turno">Por turno</option>
              <option value="semanal">Semanal</option>
              <option value="por_evento">Por evento</option>
            </select>
          </div>

          {freqTipo === "diaria" && (
            <div className="space-y-3">
              <div>
                <label className="block text-xs text-cinza mb-1">
                  Vezes por dia
                </label>
                <input
                  type="number"
                  min={1}
                  max={24}
                  value={freqDiaria.vezes_por_dia ?? 1}
                  onChange={(e) => {
                    const n = Math.max(
                      1,
                      Math.min(24, parseInt(e.target.value) || 1),
                    );
                    const janelasAtuais = freqDiaria.janelas ?? [];
                    const novasJanelas = Array.from(
                      { length: n },
                      (_, i) => janelasAtuais[i] ?? "08:00",
                    );
                    onFreqConfigChange({ vezes_por_dia: n, janelas: novasJanelas });
                  }}
                  className={inpSm + " w-24"}
                />
              </div>
              <div className="flex flex-wrap gap-3">
                {(freqDiaria.janelas ?? []).map((hora, i) => (
                  <div key={i} className="flex items-center gap-1.5">
                    <label className="text-xs text-cinza">{i + 1}ª janela</label>
                    <input
                      type="time"
                      value={hora}
                      onChange={(e) => {
                        const novasJanelas = [...(freqDiaria.janelas ?? [])];
                        novasJanelas[i] = e.target.value;
                        onFreqConfigChange({
                          vezes_por_dia: freqDiaria.vezes_por_dia ?? 1,
                          janelas: novasJanelas,
                        });
                      }}
                      className={inpSm}
                    />
                  </div>
                ))}
              </div>
            </div>
          )}

          {freqTipo === "semanal" && (
            <div>
              <label className="block text-xs text-cinza mb-1">
                Dia da semana
              </label>
              <select
                value={freqSemanal.dia_semana ?? 1}
                onChange={(e) =>
                  onFreqConfigChange({ dia_semana: parseInt(e.target.value) })
                }
                className={inpSm + " w-56"}
              >
                {DIAS_SEMANA.map((d) => (
                  <option key={d.valor} value={d.valor}>
                    {d.label}
                  </option>
                ))}
              </select>
            </div>
          )}

          {(freqTipo === "por_turno" || freqTipo === "por_evento") && (
            <p className="text-sm text-cinza">Sem configuração adicional.</p>
          )}

          {freqDirty && (
            <button
              onClick={onGuardarFreq}
              className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition"
            >
              Guardar frequência
            </button>
          )}
        </div>
      </div>

      {/* --- Itens --- */}
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-5">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-medium">
            Itens{itens.length > 0 ? ` (${itens.length})` : ""}
          </h3>
          <button
            onClick={onAdicionarItem}
            className="rounded-lg border border-teal text-teal px-3 py-1 text-sm font-medium hover:bg-teal/5 transition"
          >
            + Adicionar item
          </button>
        </div>

        {itens.length === 0 ? (
          <p className="text-cinza text-sm">
            Sem itens. Adiciona o primeiro ponto de controlo.
          </p>
        ) : (
          <div className="space-y-4">
            {itens.map((item, idx) => {
              const { aviso, erro: erroLegal } = validarContraLegal(
                item,
                limitesLegais,
              );
              return (
                <ItemEditor
                  key={item.id}
                  item={item}
                  idx={idx}
                  total={itens.length}
                  limitesLegais={limitesLegais}
                  aviso={aviso}
                  erroLegal={erroLegal}
                  onAtualizar={onAtualizarItem}
                  onLigarLimiteLegal={onLigarLimiteLegal}
                  onMover={onMoverItem}
                  onRemover={onRemoverItem}
                />
              );
            })}
          </div>
        )}
      </div>

      {/* --- Ações de versão --- */}
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-5 space-y-4">
        {/* Erro de publicação (texto multi-linha da RPC) */}
        {erroPublicacao && (
          <div
            role="alert"
            className="rounded-lg border border-red-300 bg-red-50 text-red-800 text-sm px-4 py-3 whitespace-pre-wrap"
          >
            {erroPublicacao}
          </div>
        )}

        {/* Relatório de publicação com sucesso */}
        {relatorioPublicacao && (
          <div className="rounded-lg border border-teal/30 bg-teal/5 text-sm px-4 py-3 space-y-1">
            <p className="font-semibold text-teal">
              Versão {relatorioPublicacao.numero} publicada com sucesso.
            </p>
            <p className="text-cinza">
              {relatorioPublicacao.itens} item(ns) publicado(s).
            </p>
            {relatorioPublicacao.versao_arquivada && (
              <p className="text-cinza">Versão anterior arquivada automaticamente.</p>
            )}
          </div>
        )}

        <div className="flex items-center justify-between gap-4">
          <button
            onClick={onApagarRascunho}
            disabled={busy}
            className="rounded-lg border border-red-300 text-red-700 px-4 py-1.5 text-sm font-medium hover:bg-red-50 transition disabled:opacity-50"
          >
            Apagar rascunho
          </button>

          <div className="flex items-center gap-3">
            {temErroLegal && (
              <p className="text-xs text-red-700 max-w-xs text-right">
                Corrige os erros de conformidade legal antes de publicar.
              </p>
            )}
            <button
              onClick={onPublicar}
              disabled={busy || temErroLegal}
              title={
                temErroLegal
                  ? "Existem itens com limites menos exigentes que o estatutário"
                  : undefined
              }
              className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50"
            >
              {busy ? "A publicar…" : `Publicar v.${rascunho.numero}`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================================================= ItemEditor */

function ItemEditor({
  item,
  idx,
  total,
  limitesLegais,
  aviso,
  erroLegal,
  onAtualizar,
  onLigarLimiteLegal,
  onMover,
  onRemover,
}: {
  item: Item;
  idx: number;
  total: number;
  limitesLegais: LimiteLegal[];
  aviso: string | null;
  erroLegal: string | null;
  onAtualizar: (id: string, campos: ItemUpdate) => void;
  onLigarLimiteLegal: (item: Item, legalId: string | null) => void;
  onMover: (id: string, dir: "cima" | "baixo") => void;
  onRemover: (id: string) => void;
}) {
  // Estado local para campos de texto (save on blur)
  const [texto, setTexto] = useState(item.texto);
  const [unidade, setUnidade] = useState(item.unidade ?? "");
  const [limiteMin, setLimiteMin] = useState(
    item.limite_min != null ? String(item.limite_min) : "",
  );
  const [limiteMax, setLimiteMax] = useState(
    item.limite_max != null ? String(item.limite_max) : "",
  );
  const [limiteRef, setLimiteRef] = useState(item.limite_referencia ?? "");

  // Sincronizar quando o parent actualiza o item (ex.: ligação a limite_legal)
  useEffect(() => { setTexto(item.texto); }, [item.texto]);
  useEffect(() => { setUnidade(item.unidade ?? ""); }, [item.unidade]);
  useEffect(() => {
    setLimiteMin(item.limite_min != null ? String(item.limite_min) : "");
  }, [item.limite_min]);
  useEffect(() => {
    setLimiteMax(item.limite_max != null ? String(item.limite_max) : "");
  }, [item.limite_max]);
  useEffect(() => { setLimiteRef(item.limite_referencia ?? ""); }, [item.limite_referencia]);

  const bordaClasse = erroLegal
    ? "border-red-300 bg-red-50/20"
    : aviso
      ? "border-amber-300 bg-amber-50/20"
      : "border-black/10";

  return (
    <div className={`rounded-lg border p-4 space-y-3 ${bordaClasse}`}>
      {/* Linha de controlo: ↑/↓, índice, remover */}
      <div className="flex items-center gap-2">
        <button
          onClick={() => onMover(item.id, "cima")}
          disabled={idx === 0}
          aria-label="Mover para cima"
          className="rounded border border-black/15 text-cinza px-1.5 py-0.5 text-xs hover:bg-papel transition disabled:opacity-30"
        >
          ↑
        </button>
        <button
          onClick={() => onMover(item.id, "baixo")}
          disabled={idx === total - 1}
          aria-label="Mover para baixo"
          className="rounded border border-black/15 text-cinza px-1.5 py-0.5 text-xs hover:bg-papel transition disabled:opacity-30"
        >
          ↓
        </button>
        <span className="text-xs text-cinza">#{idx + 1}</span>
        <div className="flex-1" />
        <button
          onClick={() => onRemover(item.id)}
          className="rounded border border-red-200 text-red-600 px-2 py-0.5 text-xs hover:bg-red-50 transition"
        >
          Remover
        </button>
      </div>

      {/* Texto */}
      <div>
        <label className="block text-xs text-cinza mb-1">
          Pergunta / ponto de controlo
        </label>
        <input
          type="text"
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          onBlur={() => {
            const trimado = texto.trim();
            if (trimado && trimado !== item.texto) {
              onAtualizar(item.id, { texto: trimado });
            }
          }}
          className={inp}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        {/* Tipo de resposta */}
        <div>
          <label className="block text-xs text-cinza mb-1">Tipo de resposta</label>
          <select
            value={item.tipo_resposta}
            onChange={(e) => {
              const novo = e.target.value;
              const campos: ItemUpdate = { tipo_resposta: novo };
              if (novo !== "numerico") {
                // CHECK na tabela: limites só para numerico
                campos.limite_min = null;
                campos.limite_max = null;
                campos.limite_legal_id = null;
              }
              onAtualizar(item.id, campos);
            }}
            className={inpSm + " w-full"}
          >
            {Object.entries(TIPO_RESPOSTA_LABEL).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </div>

        {/* Unidade */}
        <div>
          <label className="block text-xs text-cinza mb-1">Unidade</label>
          <input
            type="text"
            value={unidade}
            onChange={(e) => setUnidade(e.target.value)}
            onBlur={() => {
              const val = unidade.trim() || null;
              if (val !== item.unidade) onAtualizar(item.id, { unidade: val });
            }}
            placeholder="Ex.: °C, %, pH"
            className={inpSm + " w-full"}
          />
        </div>
      </div>

      {/* Limites numéricos (só para numerico) */}
      {item.tipo_resposta === "numerico" && (
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs text-cinza mb-1">Limite mínimo</label>
            <input
              type="number"
              step="any"
              value={limiteMin}
              onChange={(e) => setLimiteMin(e.target.value)}
              onBlur={() => {
                const val =
                  limiteMin.trim() === "" ? null : parseFloat(limiteMin);
                if (isNaN(val as number)) return;
                if (val !== item.limite_min) onAtualizar(item.id, { limite_min: val });
              }}
              className={inpSm + " w-full"}
            />
          </div>
          <div>
            <label className="block text-xs text-cinza mb-1">Limite máximo</label>
            <input
              type="number"
              step="any"
              value={limiteMax}
              onChange={(e) => setLimiteMax(e.target.value)}
              onBlur={() => {
                const val =
                  limiteMax.trim() === "" ? null : parseFloat(limiteMax);
                if (isNaN(val as number)) return;
                if (val !== item.limite_max) onAtualizar(item.id, { limite_max: val });
              }}
              className={inpSm + " w-full"}
            />
          </div>
        </div>
      )}

      {/* Booleano conforme (só para booleano) */}
      {item.tipo_resposta === "booleano" && (
        <div>
          <label className="flex items-start gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={item.booleano_conforme ?? true}
              onChange={(e) =>
                onAtualizar(item.id, { booleano_conforme: e.target.checked })
              }
              className="accent-teal mt-0.5 shrink-0"
            />
            <div>
              <span className="text-sm font-medium">Resposta conforme = Sim</span>
              <p className="text-xs text-cinza mt-0.5">
                Resposta que conta como conforme — desliga para perguntas em que
                &ldquo;sim&rdquo; é o problema (ex.: sinais de pragas)
              </p>
            </div>
          </label>
        </div>
      )}

      {/* Obrigatório */}
      <div>
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={item.obrigatorio}
            onChange={(e) =>
              onAtualizar(item.id, { obrigatorio: e.target.checked })
            }
            className="accent-teal"
          />
          <span className="text-sm">Obrigatório</span>
        </label>
      </div>

      {/* Proveniência */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs text-cinza mb-1">Fonte do limite</label>
          <select
            value={item.limite_fonte ?? ""}
            onChange={(e) =>
              onAtualizar(item.id, { limite_fonte: e.target.value || null })
            }
            className={inpSm + " w-full"}
          >
            <option value="">—</option>
            {Object.entries(LIMITE_FONTE_LABEL).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs text-cinza mb-1">Referência</label>
          <input
            type="text"
            value={limiteRef}
            onChange={(e) => setLimiteRef(e.target.value)}
            onBlur={() => {
              const val = limiteRef.trim() || null;
              if (val !== item.limite_referencia)
                onAtualizar(item.id, { limite_referencia: val });
            }}
            placeholder="Ex.: Portaria 1135/95"
            className={inpSm + " w-full"}
          />
        </div>
      </div>

      {/* Ligação ao limite estatutário (só para numerico) */}
      {item.tipo_resposta === "numerico" && (
        <div>
          <label className="block text-xs text-cinza mb-1">
            Limite estatutário (ligação opcional)
          </label>
          <select
            value={item.limite_legal_id ?? ""}
            onChange={(e) =>
              onLigarLimiteLegal(item, e.target.value || null)
            }
            className={inpSm + " w-full"}
          >
            <option value="">— sem ligação —</option>
            {limitesLegais.map((l) => (
              <option key={l.id} value={l.id}>
                {l.descricao} ({l.norma})
              </option>
            ))}
          </select>
          {item.limite_legal_id && (
            <p className="text-xs text-cinza mt-1">
              Ao selecionar um limite estatutário, os campos unidade, mínimo, máximo, fonte e referência são pré-preenchidos com os valores legais.
            </p>
          )}
        </div>
      )}

      {/* Avisos / erros de conformidade legal */}
      {erroLegal && (
        <div className="rounded-lg border border-red-300 bg-red-50 text-red-700 text-xs px-3 py-2">
          {erroLegal}
        </div>
      )}
      {aviso && !erroLegal && (
        <div className="rounded-lg border border-amber-300 bg-amber-50 text-amber-700 text-xs px-3 py-2">
          {aviso}
        </div>
      )}
    </div>
  );
}

/* ========================================================= VistaPublicada */

function VistaPublicada({
  publicada,
  itens,
  limitesLegais,
  busy,
  onCriarRascunho,
}: {
  publicada: Versao;
  itens: Item[];
  limitesLegais: LimiteLegal[];
  busy: boolean;
  onCriarRascunho: () => void;
}) {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-semibold">
            Versão publicada v.{publicada.numero}
          </h2>
          <span className="rounded-full bg-teal/10 text-teal text-xs px-2 py-0.5">
            publicada
          </span>
        </div>
        <button
          onClick={onCriarRascunho}
          disabled={busy}
          className="rounded-lg border border-teal text-teal px-4 py-1.5 text-sm font-medium hover:bg-teal/5 transition disabled:opacity-50"
        >
          {busy
            ? "A criar…"
            : `Criar rascunho a partir da v.${publicada.numero}`}
        </button>
      </div>

      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-5">
        {itens.length === 0 ? (
          <p className="text-cinza text-sm">Sem itens nesta versão.</p>
        ) : (
          <div className="space-y-3">
            {itens.map((item, idx) => {
              const legal = limitesLegais.find(
                (l) => l.id === item.limite_legal_id,
              );
              return (
                <div
                  key={item.id}
                  className="rounded-lg border border-black/10 p-3"
                >
                  <div className="flex items-start gap-3">
                    <span className="text-xs text-cinza mt-0.5 shrink-0">
                      #{idx + 1}
                    </span>
                    <div className="flex-1">
                      <p className="text-sm font-medium">{item.texto}</p>
                      <div className="flex flex-wrap gap-x-4 gap-y-0.5 mt-1">
                        <span className="text-xs text-cinza">
                          {TIPO_RESPOSTA_LABEL[item.tipo_resposta] ??
                            item.tipo_resposta}
                        </span>
                        {item.unidade && (
                          <span className="text-xs text-cinza">
                            Unidade: {item.unidade}
                          </span>
                        )}
                        {item.tipo_resposta === "numerico" && (
                          <>
                            {item.limite_min != null && (
                              <span className="text-xs text-cinza">
                                Mín: {item.limite_min}
                              </span>
                            )}
                            {item.limite_max != null && (
                              <span className="text-xs text-cinza">
                                Máx: {item.limite_max}
                              </span>
                            )}
                          </>
                        )}
                        {item.limite_fonte && (
                          <span className="text-xs text-cinza">
                            {LIMITE_FONTE_LABEL[item.limite_fonte] ??
                              item.limite_fonte}
                          </span>
                        )}
                        {item.limite_referencia && (
                          <span className="text-xs text-cinza">
                            {item.limite_referencia}
                          </span>
                        )}
                        {legal && (
                          <span className="text-xs text-teal">
                            {legal.descricao} ({legal.norma})
                          </span>
                        )}
                        {!item.obrigatorio && (
                          <span className="text-xs text-amber-700">Opcional</span>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
