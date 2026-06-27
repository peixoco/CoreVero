"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

const AREAS = ["cozinha", "sala", "copa", "bar", "economato", "escritório"];

export default function NovoColaborador() {
  const router = useRouter();
  const [pronto, setPronto] = useState(false);
  const [aGravar, setAGravar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [criado, setCriado] = useState<{ codigo: string; pin: string } | null>(
    null,
  );

  const [form, setForm] = useState({
    nome: "",
    area: "cozinha",
    nome_completo: "",
    posicao: "",
    contrato_inicio: "",
    contrato_fim: "",
    telefone: "",
    email: "",
  });

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) return router.replace("/login");
      setPronto(true);
    });
  }, [router]);

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

  if (!pronto) return <main className="p-6">A carregar…</main>;

  if (criado)
    return (
      <main className="p-6 max-w-md space-y-4">
        <h1 className="text-2xl font-semibold">Colaborador criado</h1>
        <div className="border rounded p-4 bg-green-50 space-y-1">
          <p>
            Código: <strong>{criado.codigo}</strong>
          </p>
          <p>
            PIN:{" "}
            <strong className="text-2xl tracking-widest">{criado.pin}</strong>
          </p>
          <p className="text-sm text-gray-600">
            Comunica este PIN ao colaborador. Podes regenerá-lo depois.
          </p>
        </div>
        <div className="flex gap-3">
          <button
            onClick={() => {
              setCriado(null);
              setForm({
                ...form,
                nome: "",
                nome_completo: "",
                posicao: "",
                telefone: "",
                email: "",
              });
            }}
            className="border rounded px-3 py-2"
          >
            Criar outro
          </button>
          <button
            onClick={() => router.push("/colaboradores")}
            className="bg-black text-white rounded px-3 py-2"
          >
            Ver lista
          </button>
        </div>
      </main>
    );

  return (
    <main className="p-6 max-w-md space-y-4">
      <h1 className="text-2xl font-semibold">Novo colaborador</h1>
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
        <button
          type="submit"
          disabled={aGravar}
          className="w-full bg-black text-white rounded py-2 disabled:opacity-50"
        >
          {aGravar ? "A criar…" : "Criar colaborador"}
        </button>
      </form>
    </main>
  );
}
