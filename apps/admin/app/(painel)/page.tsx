"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { ErroAviso, mensagemErro } from "@/lib/erros";

export default function Inicio() {
  const [colaboradores, setColaboradores] = useState<number | null>(null);
  const [picagensHoje, setPicagensHoje] = useState<number | null>(null);
  const [recusas, setRecusas] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    const inicioHoje = new Date();
    inicioHoje.setHours(0, 0, 0, 0);

    // Em erro, o KPI fica em "…" (nunca um 0 falso) e o erro é mostrado.
    supabase
      .from("trabalhador")
      .select("id", { count: "exact", head: true })
      .eq("ativo", true)
      .then(({ count, error }) => {
        if (error) return setErro(mensagemErro(error));
        setColaboradores(count ?? 0);
      });

    supabase
      .from("vista_picagem")
      .select("picagem_id", { count: "exact", head: true })
      .gte("momento_dispositivo", inicioHoje.toISOString())
      .then(({ count, error }) => {
        if (error) return setErro(mensagemErro(error));
        setPicagensHoje(count ?? 0);
      });

    supabase
      .from("picagem_recusada")
      .select("id", { count: "exact", head: true })
      .eq("estado", "pendente")
      .then(({ count, error }) => {
        if (error) return setErro(mensagemErro(error));
        setRecusas(count ?? 0);
      });
  }, []);

  return (
    <div>
      <h1 className="text-2xl font-bold mb-1">Início</h1>
      <p className="text-cinza mb-6">Visão geral do dia.</p>

      <ErroAviso erro={erro} className="mb-4" />

      {/* KPIs reais (dados que já existem hoje) */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <Kpi
          titulo="Colaboradores ativos"
          valor={colaboradores}
          href="/colaboradores"
        />
        <Kpi titulo="Picagens hoje" valor={picagensHoje} href="/registos" />
        <Kpi
          titulo="Picagens recusadas"
          valor={recusas}
          href="/registos"
          alerta={(recusas ?? 0) > 0}
        />
      </div>

      {/* Por construir — depende das frentes A (horas) e B (HACCP) */}
      <h2 className="text-sm font-semibold text-cinza uppercase tracking-wide mb-3">
        Em breve
      </h2>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <EmBreve
          titulo="Quem está a trabalhar"
          desc="Presentes e ausentes por horário. Depende do cálculo de horas."
        />
        <EmBreve
          titulo="Tarefas HACCP"
          desc="Checklists pendentes e concluídas do dia. Depende do módulo HACCP."
        />
        <EmBreve
          titulo="Vera — assistente"
          desc="A assistente que só responde de fontes citadas."
        />
      </div>
    </div>
  );
}

function Kpi({
  titulo,
  valor,
  href,
  alerta,
}: {
  titulo: string;
  valor: number | null;
  href: string;
  alerta?: boolean;
}) {
  return (
    <Link
      href={href}
      className={`block rounded-xl border bg-white shadow-sm p-5 hover:shadow transition ${alerta ? "border-red-300" : "border-black/5"}`}
    >
      <p className="text-sm text-cinza mb-1">{titulo}</p>
      <p
        className={`text-3xl font-bold ${alerta ? "text-red-700" : "text-tinta"}`}
      >
        {valor === null ? "…" : valor}
      </p>
    </Link>
  );
}

function EmBreve({ titulo, desc }: { titulo: string; desc: string }) {
  return (
    <div className="rounded-xl border border-dashed border-black/15 bg-papel/40 p-5">
      <div className="flex items-center gap-2 mb-1">
        <p className="font-semibold text-tinta">{titulo}</p>
        <span className="rounded-full bg-cinza/15 text-cinza text-xs px-2 py-0.5">
          em breve
        </span>
      </div>
      <p className="text-sm text-cinza">{desc}</p>
    </div>
  );
}
