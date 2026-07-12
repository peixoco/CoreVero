// Normalização e apresentação de erros Supabase/PostgREST no admin.
// Regra da casa: um erro nunca é engolido nem reduzido a uma contagem —
// mostra-se a mensagem completa (com código, detalhe e sugestão quando existam).

type ErroLike = {
  message?: string;
  code?: string;
  details?: string;
  hint?: string;
} | null;

export function mensagemErro(e: unknown): string {
  const err = e as ErroLike;
  if (!err) return "erro desconhecido";
  const cabeca = [err.message ?? String(e), err.code ? `(código ${err.code})` : null]
    .filter(Boolean)
    .join(" ");
  return [cabeca, err.details, err.hint].filter(Boolean).join(" — ");
}

export function ErroAviso({
  erro,
  className,
}: {
  erro: string | null;
  className?: string;
}) {
  if (!erro) return null;
  return (
    <div
      role="alert"
      className={`rounded-lg border border-red-300 bg-red-50 text-red-800 text-sm px-4 py-3 ${className ?? ""}`}
    >
      {erro}
    </div>
  );
}
