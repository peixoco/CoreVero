"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";

type Linha = {
  id: string;
  nome: string;
  codigo_pessoal: string;
  area: string | null;
  ativo: boolean;
};

export default function Colaboradores() {
  const router = useRouter();
  const [linhas, setLinhas] = useState<Linha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) return router.replace("/login");
      const { data: rows, error } = await supabase
        .from("trabalhador")
        .select("id, nome, codigo_pessoal, area, ativo")
        .order("nome");
      if (error) setErro(error.message);
      else setLinhas(rows as Linha[]);
    });
  }, [router]);

  return (
    <main className="p-6 space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Colaboradores</h1>
        <Link
          href="/colaboradores/novo"
          className="bg-black text-white rounded px-3 py-2"
        >
          + Novo
        </Link>
      </div>
      {erro && <p className="text-red-600">{erro}</p>}
      {!linhas ? (
        <p>A carregar…</p>
      ) : (
        <table className="w-full border-collapse">
          <thead>
            <tr className="text-left border-b">
              <th className="py-2">Nome</th>
              <th>Código</th>
              <th>Área</th>
              <th>Ativo</th>
            </tr>
          </thead>
          <tbody>
            {linhas.map((l) => (
              <tr key={l.id} className="border-b">
                <td className="py-2">{l.nome}</td>
                <td>{l.codigo_pessoal}</td>
                <td>{l.area ?? "—"}</td>
                <td>{l.ativo ? "sim" : "não"}</td>
              </tr>
            ))}
            {linhas.length === 0 && (
              <tr>
                <td colSpan={4} className="py-4 text-gray-500">
                  Sem colaboradores ainda.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      )}
    </main>
  );
}
