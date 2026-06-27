"use client";
import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { supabase } from "@/lib/supabase";

const AREAS = ["cozinha", "sala", "copa", "bar", "economato", "escritório"];
const inp =
  "w-full rounded-lg border border-cinza/30 bg-white px-3 py-2 outline-none focus:border-teal focus:ring-2 focus:ring-teal/20";

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
    (async () => {
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
    })();
  }, [id]);

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

  if (!pronto) return <p className="text-cinza">A carregar…</p>;

  return (
    <div className="max-w-md">
      <h1 className="text-2xl font-bold mb-6">Editar colaborador</h1>
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-5 mb-4 flex items-center gap-3 flex-wrap">
        <span
          className={`rounded-full px-2 py-0.5 text-xs ${ativo ? "bg-teal/10 text-teal" : "bg-cinza/15 text-cinza"}`}
        >
          {ativo ? "ativo" : "inativo"}
        </span>
        <button
          onClick={alternarAtivo}
          className="rounded-lg border border-cinza/40 px-3 py-1.5 text-sm hover:bg-black/5"
        >
          {ativo ? "Desativar" : "Reativar"}
        </button>
        <button
          onClick={regenerarPin}
          className="rounded-lg border border-cinza/40 px-3 py-1.5 text-sm hover:bg-black/5"
        >
          Regenerar PIN
        </button>
        {novoPin && (
          <span className="text-sm">
            Novo PIN:{" "}
            <strong className="text-teal text-lg tracking-widest">
              {novoPin}
            </strong>
          </span>
        )}
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
        <div className="flex gap-3">
          <button
            type="submit"
            disabled={aGravar}
            className="rounded-lg bg-teal text-papel px-5 py-2.5 font-medium hover:brightness-110 disabled:opacity-50"
          >
            {aGravar ? "A guardar…" : "Guardar"}
          </button>
          <button
            type="button"
            onClick={() => router.push("/colaboradores")}
            className="rounded-lg border border-cinza/40 px-5 py-2.5 hover:bg-black/5"
          >
            Voltar
          </button>
        </div>
      </form>
    </div>
  );
}
