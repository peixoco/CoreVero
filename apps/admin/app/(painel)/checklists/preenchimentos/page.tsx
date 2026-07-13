"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { ErroAviso, mensagemErro } from "@/lib/erros";

/* ================================================================== Tipos */

type RespostaResumo = {
  conforme: boolean;
};

type Instancia = {
  id: string;
  concluida_em: string | null;
  template: { nome: string } | null;
  versao: { numero: number } | null;
  loja: { nome: string } | null;
  verificacao: {
    momento_dispositivo: string;
    trabalhador: { nome: string } | null;
  } | null;
  respostas: RespostaResumo[];
};

/* ================================================================= Helpers */

function fmt(ts: string) {
  return new Date(ts).toLocaleString("pt-PT", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "Europe/Lisbon",
  });
}

/* ================================================================== Página */

export default function Preenchimentos() {
  const [instancias, setInstancias] = useState<Instancia[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const router = useRouter();

  useEffect(() => {
    supabase
      .from("checklist_instancia")
      .select(
        // FK compostas: embeds pelo nome exato da constraint (padrão do R2a).
        // Reverse embed de checklist_resposta: hint com !constraint para desambiguar
        // (checklist_resposta tem FK para checklist_instancia e para checklist_item).
        `id, concluida_em,
         template:checklist_instancia_empresa_id_template_id_fkey(nome),
         versao:checklist_instancia_empresa_id_versao_id_fkey(numero),
         loja:checklist_instancia_empresa_id_loja_id_fkey(nome),
         verificacao:checklist_instancia_empresa_id_verificacao_id_fkey(
           momento_dispositivo,
           trabalhador:verificacao_empresa_id_trabalhador_id_fkey(nome)
         ),
         respostas:checklist_resposta!checklist_resposta_empresa_id_instancia_id_fkey(conforme)`,
      )
      .eq("estado", "concluida")
      .order("concluida_em", { ascending: false })
      .limit(50)
      .then(({ data, error }) => {
        if (error) setErro(mensagemErro(error));
        else setInstancias(data as unknown as Instancia[]);
      });
  }, []);

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-2xl font-bold">Checklists HACCP</h1>
      </div>

      {/* Navegação entre Templates e Preenchimentos */}
      <div className="flex gap-1 border-b border-black/10 mb-6">
        <Link
          href="/checklists"
          className="px-4 py-2 text-sm font-medium border-b-2 border-transparent text-cinza hover:text-tinta -mb-px transition"
        >
          Templates
        </Link>
        <Link
          href="/checklists/preenchimentos"
          className="px-4 py-2 text-sm font-medium border-b-2 border-teal text-tinta -mb-px transition"
        >
          Preenchimentos
        </Link>
      </div>

      <ErroAviso erro={erro} className="mb-4" />

      {!instancias ? (
        <p className="text-cinza">A carregar…</p>
      ) : (
        <div className="bg-white rounded-xl border border-black/5 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-cinza border-b border-black/5">
                <th className="px-4 py-3 font-medium">Template (versão)</th>
                <th className="px-4 py-3 font-medium">Loja</th>
                <th className="px-4 py-3 font-medium">Preenchido por</th>
                <th className="px-4 py-3 font-medium">Concluído em</th>
                <th className="px-4 py-3 font-medium">N/C</th>
              </tr>
            </thead>
            <tbody>
              {instancias.map((inst) => {
                const nNaoConformes = inst.respostas.filter(
                  (r) => !r.conforme,
                ).length;
                return (
                  <tr
                    key={inst.id}
                    onClick={() =>
                      router.push(`/checklists/preenchimentos/${inst.id}`)
                    }
                    className="border-b border-black/5 last:border-0 hover:bg-papel/50 cursor-pointer"
                  >
                    <td className="px-4 py-3 font-medium">
                      {inst.template?.nome ?? "—"}
                      {inst.versao && (
                        <span className="ml-1.5 font-normal text-cinza">
                          v.{inst.versao.numero}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-cinza">
                      {inst.loja?.nome ?? "—"}
                    </td>
                    <td className="px-4 py-3">
                      {inst.verificacao?.trabalhador?.nome ?? (
                        <span className="text-cinza">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-cinza">
                      {inst.concluida_em ? fmt(inst.concluida_em) : "—"}
                    </td>
                    <td className="px-4 py-3">
                      {nNaoConformes > 0 ? (
                        <span className="inline-flex items-center rounded-full bg-red-100 text-red-700 text-xs px-2 py-0.5 font-medium">
                          {nNaoConformes} N/C
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-full bg-teal/10 text-teal text-xs px-2 py-0.5 font-medium">
                          Conforme
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })}
              {instancias.length === 0 && (
                <tr>
                  <td
                    colSpan={5}
                    className="px-4 py-8 text-cinza text-center"
                  >
                    Sem preenchimentos concluídos. O kiosk ainda não registou
                    nenhuma checklist.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          {instancias.length === 50 && (
            <div className="px-4 py-2 border-t border-black/5 bg-papel/40 text-xs text-cinza">
              A mostrar os últimos 50 preenchimentos. O relatório completo
              está disponível no R2c.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
