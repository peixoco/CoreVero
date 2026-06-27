"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

const AREAS = ["cozinha", "sala", "copa", "bar", "economato", "escritório"];
const inp =
  "w-full rounded-lg border border-cinza/30 bg-white px-3 py-2 outline-none focus:border-teal focus:ring-2 focus:ring-teal/20";

export default function NovoColaborador() {
  const router = useRouter();
  const [aGravar, setAGravar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [criado, setCriado] = useState<{ codigo: string; pin: string } | null>(
    null,
  );
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

  function set(k: string, v: string) {
    setForm((f) => ({ ...f, [k]: v }));
  }
  const nn = (v: string) => (v.trim() === "" ? null : v.trim());

  async function gravar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setAGravar(true);
    const { data, error } = await supabase.rpc("criar_colaborador", {
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
    const row = Array.isArray(data) ? data[0] : data;
    setCriado({ codigo: row.codigo_pessoal, pin: row.pin });
  }

  if (criado)
    return (
      <div className="max-w-md">
        <h1 className="text-2xl font-bold mb-6">Colaborador criado</h1>
        <div className="bg-white rounded-xl border border-teal/30 shadow-sm p-6">
          <p className="text-cinza text-sm">Código</p>
          <p className="text-xl font-semibold mb-3">{criado.codigo}</p>
          <p className="text-cinza text-sm">PIN</p>
          <p className="text-3xl font-bold tracking-[0.3em] text-teal">
            {criado.pin}
          </p>
          <p className="text-sm text-cinza pt-3">
            Comunica este PIN ao colaborador. Podes regenerá-lo depois.
          </p>
        </div>
        <div className="flex gap-3 mt-4">
          <button
            onClick={() => {
              setCriado(null);
              setForm({
                ...form,
                nome: "",
                nome_completo: "",
                data_nascimento: "",
                posicao: "",
                telefone: "",
                email: "",
              });
            }}
            className="rounded-lg border border-cinza/40 px-4 py-2 hover:bg-black/5"
          >
            Criar outro
          </button>
          <button
            onClick={() => router.push("/colaboradores")}
            className="rounded-lg bg-teal text-papel px-4 py-2 hover:brightness-110"
          >
            Ver lista
          </button>
        </div>
      </div>
    );

  return (
    <div className="max-w-md">
      <h1 className="text-2xl font-bold mb-6">Novo colaborador</h1>
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
        <button
          type="submit"
          disabled={aGravar}
          className="w-full rounded-lg bg-teal text-papel py-2.5 font-medium hover:brightness-110 disabled:opacity-50"
        >
          {aGravar ? "A criar…" : "Criar colaborador"}
        </button>
      </form>
    </div>
  );
}
