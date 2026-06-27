"use client";
import { useEffect, useState } from "react";
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
  const [linhas, setLinhas] = useState<Linha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    supabase
      .from("trabalhador")
      .select("id, nome, codigo_pessoal, area, ativo")
      .order("nome")
      .then(({ data, error }) => {
        if (error) setErro(error.message);
        else setLinhas(data as Linha[]);
      });
  }, []);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Colaboradores</h1>
        <Link
          href="/colaboradores/novo"
          className="rounded-lg bg-teal text-papel px-4 py-2 font-medium hover:brightness-110 transition"
        >
          + Novo
        </Link>
      </div>
      {erro && <p className="text-red-600 mb-4">{erro}</p>}
      {!linhas ? (
        <p className="text-cinza">A carregar…</p>
      ) : (
        <div className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-cinza border-b border-black/5">
                <th className="px-4 py-3 font-medium">Nome</th>
                <th className="px-4 py-3 font-medium">Código</th>
                <th className="px-4 py-3 font-medium">Área</th>
                <th className="px-4 py-3 font-medium">Estado</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <tr
                  key={l.id}
                  className="border-b border-black/5 last:border-0 hover:bg-papel/50"
                >
                  <td className="px-4 py-3">
                    <Link
                      href={`/colaboradores/${l.id}`}
                      className="font-medium hover:text-teal"
                    >
                      {l.nome}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-cinza">{l.codigo_pessoal}</td>
                  <td className="px-4 py-3 text-cinza">{l.area ?? "—"}</td>
                  <td className="px-4 py-3">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs ${l.ativo ? "bg-teal/10 text-teal" : "bg-cinza/15 text-cinza"}`}
                    >
                      {l.ativo ? "ativo" : "inativo"}
                    </span>
                  </td>
                </tr>
              ))}
              {linhas.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-4 py-6 text-cinza">
                    Sem colaboradores ainda.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
