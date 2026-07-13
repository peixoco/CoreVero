"use client";
import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { ErroAviso, mensagemErro } from "@/lib/erros";

/* ================================================================== Tipos */

type InstanciaDetalhe = {
  id: string;
  concluida_em: string | null;
  template: { nome: string } | null;
  versao: { numero: number } | null;
  loja: { nome: string } | null;
  verificacao: {
    momento_dispositivo: string;
    momento_servidor: string;
    foto_url: string | null;
    trabalhador: { nome: string } | null;
  } | null;
};

type RespostaDetalhe = {
  id: string;
  valor: string | null;
  conforme: boolean;
  item: {
    ordem: number;
    texto: string;
    tipo_resposta: string;
    unidade: string | null;
  } | null;
  acoes: { descricao: string }[];
};

/* ================================================================= Helpers */

function fmt(ts: string) {
  return new Date(ts).toLocaleString("pt-PT", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "Europe/Lisbon",
  });
}

function valorFormatado(
  valor: string | null,
  tipoResposta: string,
  unidade: string | null,
): string {
  if (valor === null || valor === "") return "—";
  if (tipoResposta === "numerico") {
    return unidade ? `${valor} ${unidade}` : valor;
  }
  if (tipoResposta === "booleano") {
    return valor === "true" ? "Sim" : valor === "false" ? "Não" : valor;
  }
  return valor;
}

/* ================================================================== Página */

export default function PreenchimentoDetalhe() {
  const { id } = useParams<{ id: string }>();

  const [instancia, setInstancia] = useState<InstanciaDetalhe | null>(null);
  const [respostas, setRespostas] = useState<RespostaDetalhe[]>([]);
  const [loading, setLoading] = useState(true);
  const [erro, setErro] = useState<string | null>(null);

  // Estado da foto de atribuição
  const [fotoSignedUrl, setFotoSignedUrl] = useState<string | null>(null);
  const [fotoPurgada, setFotoPurgada] = useState(false);
  const [fotoErro, setFotoErro] = useState<string | null>(null);

  /* --------------------------------------------------------- Carregamento */

  const carregarInstancia = useCallback(async () => {
    const { data, error } = await supabase
      .from("checklist_instancia")
      .select(
        // FK compostas — nome exato da constraint (padrão do R2a).
        // Nested embed: verificacao → trabalhador (ambas FK compostas).
        `id, concluida_em,
         template:checklist_instancia_empresa_id_template_id_fkey(nome),
         versao:checklist_instancia_empresa_id_versao_id_fkey(numero),
         loja:checklist_instancia_empresa_id_loja_id_fkey(nome),
         verificacao:checklist_instancia_empresa_id_verificacao_id_fkey(
           momento_dispositivo,
           momento_servidor,
           foto_url,
           trabalhador:verificacao_empresa_id_trabalhador_id_fkey(nome)
         )`,
      )
      .eq("id", id)
      .single();
    if (error) setErro(mensagemErro(error));
    else setInstancia(data as unknown as InstanciaDetalhe);
    return data as unknown as InstanciaDetalhe | null;
  }, [id]);

  const carregarRespostas = useCallback(async () => {
    const { data, error } = await supabase
      .from("checklist_resposta")
      .select(
        // Forward embed para checklist_item (FK composta).
        // Reverse embed para acao_corretiva (hint com ! para desambiguar:
        // acao_corretiva tem FK para checklist_resposta E para verificacao).
        `id, valor, conforme,
         item:checklist_resposta_empresa_id_item_id_fkey(
           ordem, texto, tipo_resposta, unidade
         ),
         acoes:acao_corretiva!acao_corretiva_empresa_id_resposta_id_fkey(
           descricao
         )`,
      )
      .eq("instancia_id", id);
    if (error) setErro(mensagemErro(error));
    else {
      const ordenadas = ((data as unknown as RespostaDetalhe[]) ?? []).sort(
        (a, b) => (a.item?.ordem ?? 0) - (b.item?.ordem ?? 0),
      );
      setRespostas(ordenadas);
    }
  }, [id]);

  useEffect(() => {
    setLoading(true);
    setErro(null);
    Promise.all([carregarInstancia(), carregarRespostas()]).then(
      ([instanciaCarregada]) => {
        setLoading(false);
        // Só depois de ter o instancia é que temos o foto_url da verificacao
        // (já está disponível no estado via setInstancia; usamos o retorno direto)
        if (instanciaCarregada?.verificacao?.foto_url) {
          resolverFoto(instanciaCarregada.verificacao.foto_url);
        }
      },
    );
  }, [carregarInstancia, carregarRespostas]);

  /* ------------------------------------------- Foto de atribuição */

  async function resolverFoto(path: string) {
    const { data, error } = await supabase.storage
      .from("picagens")
      .createSignedUrl(path, 300); // 5 minutos de validade enquanto a página está aberta
    if (error || !data?.signedUrl) {
      setFotoPurgada(true);
      setFotoErro("Foto não disponível (possível purga por retenção).");
    } else {
      setFotoSignedUrl(data.signedUrl);
    }
  }

  /* --------------------------------------------------------------- Render */

  if (loading) {
    return <p className="text-cinza">A carregar…</p>;
  }

  if (!instancia) {
    return (
      <div>
        <ErroAviso erro={erro} />
        <p className="text-cinza mt-4">Preenchimento não encontrado.</p>
      </div>
    );
  }

  const nNaoConformes = respostas.filter((r) => !r.conforme).length;

  return (
    <div className="space-y-6">
      {/* Fio de migalhas */}
      <nav className="flex items-center gap-2 text-sm text-cinza">
        <Link href="/checklists" className="hover:text-tinta">
          Checklists
        </Link>
        <span>/</span>
        <Link href="/checklists/preenchimentos" className="hover:text-tinta">
          Preenchimentos
        </Link>
        <span>/</span>
        <span className="text-tinta">
          {instancia.template?.nome ?? "Preenchimento"}
        </span>
      </nav>

      <ErroAviso erro={erro} className="mb-2" />

      {/* Cabeçalho */}
      <div className="bg-white rounded-xl border border-black/5 shadow-sm p-6">
        <div className="flex items-start justify-between gap-4 mb-4">
          <div>
            <h1 className="text-xl font-bold text-tinta">
              {instancia.template?.nome ?? "—"}
              {instancia.versao && (
                <span className="ml-2 text-base font-normal text-cinza">
                  v.{instancia.versao.numero}
                </span>
              )}
            </h1>
            <p className="text-sm text-cinza mt-0.5">
              Loja:{" "}
              <span className="font-medium text-tinta">
                {instancia.loja?.nome ?? "—"}
              </span>
            </p>
          </div>
          {nNaoConformes > 0 ? (
            <span className="inline-flex items-center rounded-full bg-red-100 text-red-700 text-sm px-3 py-1 font-medium shrink-0">
              {nNaoConformes} não conforme{nNaoConformes > 1 ? "s" : ""}
            </span>
          ) : (
            <span className="inline-flex items-center rounded-full bg-teal/10 text-teal text-sm px-3 py-1 font-medium shrink-0">
              Totalmente conforme
            </span>
          )}
        </div>

        <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
          <div>
            <span className="text-cinza">Preenchido por</span>
            <p className="font-medium">
              {instancia.verificacao?.trabalhador?.nome ?? "—"}
            </p>
          </div>
          <div>
            <span className="text-cinza">Concluído em</span>
            <p className="font-medium">
              {instancia.concluida_em ? fmt(instancia.concluida_em) : "—"}
            </p>
          </div>
          {instancia.verificacao && (
            <>
              <div>
                <span className="text-cinza">Hora do dispositivo</span>
                <p className="font-medium">
                  {fmt(instancia.verificacao.momento_dispositivo)}
                </p>
              </div>
              <div>
                <span className="text-cinza">Hora do servidor</span>
                <p className="font-medium">
                  {fmt(instancia.verificacao.momento_servidor)}
                </p>
              </div>
            </>
          )}
        </div>

        {/* Foto de atribuição */}
        {instancia.verificacao?.foto_url && (
          <div className="mt-4 pt-4 border-t border-black/5">
            <p className="text-xs text-cinza mb-2">
              Foto de atribuição (verificação de identidade)
            </p>
            {fotoPurgada || fotoErro ? (
              <div className="inline-flex items-center gap-2 rounded-lg border border-black/10 bg-papel/60 px-4 py-3 text-sm text-cinza">
                <span>Foto não disponível</span>
                {fotoErro && (
                  <span className="text-xs">— {fotoErro}</span>
                )}
              </div>
            ) : fotoSignedUrl ? (
              <div className="inline-block">
                <a
                  href={fotoSignedUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="block"
                >
                  <img
                    src={fotoSignedUrl}
                    alt="Foto de atribuição"
                    className="h-24 w-24 rounded-lg object-cover border border-black/10 hover:opacity-90 transition"
                    onError={() => {
                      setFotoSignedUrl(null);
                      setFotoPurgada(true);
                      setFotoErro(
                        "Ficheiro purgado pela política de retenção.",
                      );
                    }}
                  />
                </a>
                <p className="text-xs text-cinza mt-1">
                  Clica para ver em tamanho real
                </p>
              </div>
            ) : (
              <div className="inline-flex items-center gap-2 rounded-lg border border-black/10 bg-papel/60 px-4 py-3 text-sm text-cinza">
                <span>A carregar foto…</span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Lista de respostas */}
      <div>
        <h2 className="text-lg font-semibold mb-3">
          Respostas{" "}
          <span className="font-normal text-cinza text-base">
            ({respostas.length})
          </span>
        </h2>
        <div className="space-y-2">
          {respostas.length === 0 ? (
            <div className="rounded-xl border border-dashed border-black/15 bg-papel/40 p-6 text-center">
              <p className="text-cinza text-sm">Sem respostas registadas.</p>
            </div>
          ) : (
            respostas.map((resp, idx) => {
              const textoItem = resp.item?.texto ?? "Item desconhecido";
              const tipoResposta = resp.item?.tipo_resposta ?? "texto";
              const unidade = resp.item?.unidade ?? null;
              const valor = valorFormatado(resp.valor, tipoResposta, unidade);
              const temAcao = resp.acoes.length > 0;

              return (
                <div
                  key={resp.id}
                  className={`rounded-lg border p-4 ${
                    resp.conforme
                      ? "border-black/10 bg-white"
                      : "border-red-200 bg-red-50/40"
                  }`}
                >
                  <div className="flex items-start gap-3">
                    {/* Índice */}
                    <span className="text-xs text-cinza mt-0.5 shrink-0 w-6">
                      #{idx + 1}
                    </span>

                    <div className="flex-1 min-w-0">
                      {/* Texto do item */}
                      <p className="text-sm font-medium text-tinta">
                        {textoItem}
                      </p>

                      {/* Valor + conformidade */}
                      <div className="flex items-center gap-3 mt-1.5 flex-wrap">
                        <span className="text-sm text-cinza">
                          Resposta:{" "}
                          <span className="font-medium text-tinta">
                            {valor}
                          </span>
                        </span>
                        {resp.conforme ? (
                          <span className="inline-flex items-center rounded-full bg-teal/10 text-teal text-xs px-2 py-0.5 font-medium">
                            Conforme
                          </span>
                        ) : (
                          <span className="inline-flex items-center rounded-full bg-red-100 text-red-700 text-xs px-2 py-0.5 font-medium">
                            Não conforme
                          </span>
                        )}
                      </div>

                      {/* Ação corretiva (quando não conforme) */}
                      {!resp.conforme && (
                        <div className="mt-2">
                          {temAcao ? (
                            resp.acoes.map((acao, ai) => (
                              <div
                                key={ai}
                                className="mt-1 flex items-start gap-2 text-sm"
                              >
                                <span className="shrink-0 text-cinza">
                                  Ação corretiva:
                                </span>
                                <span className="text-tinta font-medium">
                                  {acao.descricao}
                                </span>
                              </div>
                            ))
                          ) : (
                            <p className="mt-1 text-xs text-amber-700">
                              Sem ação corretiva registada.
                            </p>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
