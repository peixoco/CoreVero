"use client";
import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { ErroAviso, mensagemErro } from "@/lib/erros";

/* ------------------------------------------------------------------ Tipos */

type VersaoResumo = {
  id: string;
  numero: number;
  estado: string;
};

type TemplateRow = {
  id: string;
  nome: string;
  ativo: boolean;
  loja_id: string | null;
  loja: { nome: string } | null;
  versoes: VersaoResumo[];
};

type Loja = { id: string; nome: string };

/* ---------------------------------------------------------------- Helpers */

const inp =
  "w-full rounded-lg border border-black/15 bg-white px-3 py-2 text-sm outline-none focus:border-teal focus:ring-2 focus:ring-teal/20";

/* ================================================================= Página */

export default function Checklists() {
  const [templates, setTemplates] = useState<TemplateRow[] | null>(null);
  const [lojas, setLojas] = useState<Loja[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [modalAberto, setModalAberto] = useState(false);
  const [instalando, setInstalando] = useState(false);
  const [resultadoInstalacao, setResultadoInstalacao] = useState<string | null>(null);
  const router = useRouter();

  async function instalarBiblioteca() {
    setInstalando(true);
    setErro(null);
    setResultadoInstalacao(null);
    const { data, error } = await supabase.rpc("instalar_templates_base");
    setInstalando(false);
    if (error) return setErro(mensagemErro(error));
    const res = data as {
      instalados: number;
      templates?: string[];
      nota?: string;
      motivo?: string;
    };
    if (res.instalados > 0) {
      setResultadoInstalacao(
        `${res.instalados} templates instalados em rascunho: ${(res.templates ?? []).join(", ")}.` +
          (res.nota ? ` ${res.nota}.` : ""),
      );
    } else {
      setResultadoInstalacao(res.motivo ?? "Nada instalado.");
    }
    carregar();
  }

  function carregar() {
    supabase
      .from("checklist_template")
      .select(
        // FK composta (empresa_id, loja_id) → o PostgREST não resolve o embed
        // pelo nome da coluna; é preciso o nome da constraint
        "id, nome, ativo, loja_id, loja:checklist_template_empresa_id_loja_id_fkey(nome), versoes:checklist_template_versao(id, numero, estado)",
      )
      .order("nome")
      .then(({ data, error }) => {
        if (error) setErro(mensagemErro(error));
        else setTemplates(data as unknown as TemplateRow[]);
      });
  }

  useEffect(() => {
    carregar();
    supabase
      .from("loja")
      .select("id, nome")
      .eq("ativa", true)
      .order("nome")
      .then(({ data, error }) => {
        if (error) setErro(mensagemErro(error));
        else setLojas((data as Loja[]) ?? []);
      });
  }, []);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Checklists HACCP</h1>
        <div className="flex gap-2">
          <button
            onClick={instalarBiblioteca}
            disabled={instalando}
            className="rounded-lg border border-black/15 text-tinta px-4 py-2 font-medium hover:bg-papel transition disabled:opacity-50"
            title="Cria os 7 templates de arranque (doc 04) em rascunho — nada é publicado automaticamente"
          >
            {instalando ? "A instalar…" : "Instalar biblioteca base"}
          </button>
          <button
            onClick={() => setModalAberto(true)}
            className="rounded-lg bg-teal text-papel px-4 py-2 font-medium hover:brightness-110 transition"
          >
            + Novo template
          </button>
        </div>
      </div>

      <ErroAviso erro={erro} className="mb-4" />
      {resultadoInstalacao && (
        <div className="mb-4 rounded-lg border border-teal/30 bg-teal/5 text-tinta text-sm px-4 py-3 whitespace-pre-wrap">
          {resultadoInstalacao}
        </div>
      )}

      {!templates ? (
        <p className="text-cinza">A carregar…</p>
      ) : (
        <div className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-cinza border-b border-black/5">
                <th className="px-4 py-3 font-medium">Nome</th>
                <th className="px-4 py-3 font-medium">Âmbito</th>
                <th className="px-4 py-3 font-medium">Publicada</th>
                <th className="px-4 py-3 font-medium">Rascunho</th>
                <th className="px-4 py-3 font-medium">Estado</th>
              </tr>
            </thead>
            <tbody>
              {templates.map((t) => {
                const publicada = t.versoes.find((v) => v.estado === "publicada");
                const rascunho = t.versoes.find((v) => v.estado === "rascunho");
                return (
                  <tr
                    key={t.id}
                    onClick={() => router.push(`/checklists/${t.id}`)}
                    className="border-b border-black/5 last:border-0 hover:bg-papel/50 cursor-pointer"
                  >
                    <td className="px-4 py-3 font-medium">{t.nome}</td>
                    <td className="px-4 py-3 text-cinza">
                      {t.loja ? t.loja.nome : "Empresa"}
                    </td>
                    <td className="px-4 py-3 text-cinza">
                      {publicada ? `v.${publicada.numero}` : "—"}
                    </td>
                    <td className="px-4 py-3">
                      {rascunho ? (
                        <span className="text-amber-700">
                          v.{rascunho.numero} em edição
                        </span>
                      ) : (
                        <span className="text-cinza">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs ${
                          t.ativo
                            ? "bg-teal/10 text-teal"
                            : "bg-cinza/15 text-cinza"
                        }`}
                      >
                        {t.ativo ? "ativo" : "inativo"}
                      </span>
                    </td>
                  </tr>
                );
              })}
              {templates.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-6 text-cinza text-center">
                    Sem templates. Cria o primeiro com o botão acima.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {modalAberto && (
        <NovoTemplateModal
          lojas={lojas}
          onClose={() => setModalAberto(false)}
          onDone={(id) => {
            setModalAberto(false);
            router.push(`/checklists/${id}`);
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
}: {
  titulo: string;
  onClose: () => void;
  children: ReactNode;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-auto bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className="mt-10 w-full max-w-md rounded-2xl bg-white shadow-xl"
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

/* --------------------------------------------------------- Novo template */

function NovoTemplateModal({
  lojas,
  onClose,
  onDone,
}: {
  lojas: Loja[];
  onClose: () => void;
  onDone: (id: string) => void;
}) {
  const [nome, setNome] = useState("");
  const [lojaId, setLojaId] = useState("");
  const [busy, setBusy] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function criar() {
    if (!nome.trim()) return setErro("O nome é obrigatório.");
    setBusy(true);
    setErro(null);

    // Obter empresa_id do utilizador autenticado
    const { data: empId, error: empErr } = await supabase.rpc("empresa_atual");
    if (empErr) {
      setBusy(false);
      return setErro(mensagemErro(empErr));
    }
    const empresaId = empId as string;

    // Criar o template
    const { data: t, error: tErr } = await supabase
      .from("checklist_template")
      .insert({
        empresa_id: empresaId,
        nome: nome.trim(),
        loja_id: lojaId || null,
      })
      .select("id")
      .single();
    if (tErr) {
      setBusy(false);
      return setErro(mensagemErro(tErr));
    }

    // Criar versão 1 como rascunho — NÃO incluir campo estado (grant de coluna)
    const { error: vErr } = await supabase
      .from("checklist_template_versao")
      .insert({
        empresa_id: empresaId,
        template_id: t.id,
        numero: 1,
        frequencia_tipo: "diaria",
        frequencia_config: { vezes_por_dia: 1, janelas: ["08:00"] },
      });
    if (vErr) {
      setBusy(false);
      return setErro(mensagemErro(vErr));
    }

    setBusy(false);
    onDone(t.id);
  }

  return (
    <Modal titulo="Novo template de checklist" onClose={onClose}>
      <div className="space-y-4">
        <div>
          <label className="block text-xs text-cinza mb-1">Nome</label>
          <input
            type="text"
            value={nome}
            onChange={(e) => setNome(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && !busy && criar()}
            className={inp}
            placeholder="Ex.: Temperatura óleo de fritura"
            autoFocus
          />
        </div>
        <div>
          <label className="block text-xs text-cinza mb-1">Âmbito</label>
          <select
            value={lojaId}
            onChange={(e) => setLojaId(e.target.value)}
            className={inp}
          >
            <option value="">Empresa (aplica-se a todas as lojas)</option>
            {lojas.map((l) => (
              <option key={l.id} value={l.id}>
                {l.nome}
              </option>
            ))}
          </select>
        </div>

        <ErroAviso erro={erro} />

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="rounded-lg border border-black/15 text-tinta px-4 py-1.5 text-sm font-medium hover:bg-papel transition"
          >
            Cancelar
          </button>
          <button
            onClick={criar}
            disabled={busy}
            className="rounded-lg bg-teal text-white px-4 py-1.5 text-sm font-medium hover:opacity-90 transition disabled:opacity-50"
          >
            {busy ? "A criar…" : "Criar"}
          </button>
        </div>
      </div>
    </Modal>
  );
}
