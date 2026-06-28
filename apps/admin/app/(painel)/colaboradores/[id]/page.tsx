"use client";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";

export default function Colaborador() {
  const { id } = useParams<{ id: string }>();
  const [nome, setNome] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    supabase
      .from("trabalhador")
      .select("nome")
      .eq("id", id)
      .maybeSingle()
      .then(({ data }) => setNome((data as { nome: string } | null)?.nome ?? "—"));
  }, [id]);

  const TABS = ["Informação", "PIN / Picagem", "Documentos", "Horário", "Férias"];

  return (
    <div>
      <Link href="/colaboradores" className="text-sm text-cinza hover:text-tinta">
        ← Colaboradores
      </Link>
      <h1 className="text-2xl font-bold mt-2 mb-4">{nome ?? "…"}</h1>

      <div className="flex gap-1 border-b border-black/10 mb-6">
        {TABS.map((t, i) => (
          <span
            key={t}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px ${
              i === 0 ? "border-teal text-tinta" : "border-transparent text-cinza"
            }`}
          >
            {t}
          </span>
        ))}
      </div>

      <div className="rounded-xl border border-dashed border-black/15 bg-papel/40 p-8 text-center">
        <div className="flex items-center justify-center gap-2 mb-2">
          <p className="font-semibold text-tinta">Página do colaborador</p>
          <span className="rounded-full bg-cinza/15 text-cinza text-xs px-2 py-0.5">
            em construção
          </span>
        </div>
        <p className="text-sm text-cinza max-w-md mx-auto">
          As 5 tabs (Informação, PIN/Picagem, Documentos, Horário, Férias)
          dependem da camada de dados de RH — tabela cifrada de dados fiscais,
          bucket de documentos, horário e férias. Frente C do roadmap.
        </p>
      </div>
    </div>
  );
}
