"use client";
import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { supabase } from "@/lib/supabase";

const AREAS = ["cozinha", "sala", "copa", "bar", "economato", "escritório"];

export default function EditarColaborador() {
  const router = useRouter();
  const id = useParams().id as string;

  const [pronto, setPronto] = useState(false);
  const [aGravar, setAGravar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [ativo, setAtivo] = useState(true);
  const [novoPin, setNovoPin] = useState<string | null>(null);

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
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) return router.replace("/login");
      const { data: t, error: e1 } = await supabase
        .from("trabalhador")
        .select("nome, area, ativo")
        .eq("id", id)
        .single();
      if (e1 || !t) {
        setErro(e1?.message ?? "não encontrado");
        setPronto(true);
        return;
      }
      const { data: d } = await supabase
        .from("trabalhador_detalhe")
        .select("*")
        .eq("trabalhador_id", id)
        .maybeSingle();
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
    });
  }, [id, router]);

  function set(k: string, v: string) {
    setForm((f) => ({ ...f, [k]: v }));
  }
  const nn = (v: string) => (v.trim() === "" ? null : v.trim());

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

  async function regenerarPin() {
    setErro(null);
    setMsg(null);
    setNovoPin(null);
    const { data, error } = await supabase.rpc("gerar_novo_pin", {
      p_trabalhador_id: id,
    });
    if (error) return setErro(error.message);
    setNovoPin(data as string);
  }

  if (!pronto) return <main className="p-6">A carregar…</main>;

  return (
    <main className="p-6 max-w-md space-y-4">
      <h1 className="text-2xl font-semibold">Editar colaborador</h1>

      <div className="flex items-center gap-3">
        <span className={ativo ? "text-green-700" : "text-gray-500"}>
          {ativo ? "Ativo" : "Inativo"}
        </span>
        <button onClick={alternarAtivo} className="border rounded px-3 py-1">
          {ativo ? "Desativar" : "Reativar"}
        </button>
        <button onClick={regenerarPin} className="border rounded px-3 py-1">
          Regenerar PIN
        </button>
      </div>
      {novoPin && (
        <p>
          Novo PIN:{" "}
          <strong className="text-xl tracking-widest">{novoPin}</strong> —
          comunica ao colaborador.
        </p>
      )}

      <form onSubmit={gravar} className="space-y-3">
        <label className="block">
          Nome (kiosk) *
          <input
            required
            value={form.nome}
            onChange={(e) => set("nome", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          />
        </label>
        <label className="block">
          Área *
          <select
            value={form.area}
            onChange={(e) => set("area", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          >
            {AREAS.map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          Nome completo
          <input
            value={form.nome_completo}
            onChange={(e) => set("nome_completo", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          />
        </label>
        <label className="block">
          Data de nascimento
          <input
            type="date"
            value={form.data_nascimento}
            onChange={(e) => set("data_nascimento", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          />
        </label>
        <label className="block">
          Posição
          <input
            value={form.posicao}
            onChange={(e) => set("posicao", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          />
        </label>
        <div className="flex gap-3">
          <label className="block flex-1">
            Início contrato
            <input
              type="date"
              value={form.contrato_inicio}
              onChange={(e) => set("contrato_inicio", e.target.value)}
              className="w-full border rounded px-3 py-2 mt-1"
            />
          </label>
          <label className="block flex-1">
            Fim contrato
            <input
              type="date"
              value={form.contrato_fim}
              onChange={(e) => set("contrato_fim", e.target.value)}
              className="w-full border rounded px-3 py-2 mt-1"
            />
          </label>
        </div>
        <label className="block">
          Telefone
          <input
            value={form.telefone}
            onChange={(e) => set("telefone", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          />
        </label>
        <label className="block">
          Email
          <input
            type="email"
            value={form.email}
            onChange={(e) => set("email", e.target.value)}
            className="w-full border rounded px-3 py-2 mt-1"
          />
        </label>
        {erro && <p className="text-red-600 text-sm">{erro}</p>}
        {msg && <p className="text-green-700 text-sm">{msg}</p>}
        <div className="flex gap-3">
          <button
            type="submit"
            disabled={aGravar}
            className="bg-black text-white rounded px-4 py-2 disabled:opacity-50"
          >
            {aGravar ? "A guardar…" : "Guardar"}
          </button>
          <button
            type="button"
            onClick={() => router.push("/colaboradores")}
            className="border rounded px-4 py-2"
          >
            Voltar
          </button>
        </div>
      </form>
    </main>
  );
}
