// conformidade.ts — Avaliação local de conformidade de itens de checklist HACCP.
//
// ATENÇÃO: Esta função é apenas para feedback UX imediato ao colaborador.
// A AUTORIDADE de conformidade é sempre o servidor (função SQL avaliar_conformidade,
// migração 20260713210000_motor_conformidade_kiosk.sql §1).
// O kiosk NUNCA envia o campo "conforme" — o servidor avalia de raiz.
//
// A lógica implementada aqui espelha FIELMENTE os 4 braços da função SQL.
// Qualquer divergência entre esta função e a SQL é um bug.

import type { Database } from "./database.types";

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

/**
 * Subconjunto dos campos de checklist_item necessários para a avaliação de
 * conformidade e para a renderização do formulário no kiosk.
 * Derivado do Row gerado pelo Supabase (database.types.ts).
 */
export type ItemChecklist = Pick<
  Database["public"]["Tables"]["checklist_item"]["Row"],
  | "id"
  | "ordem"
  | "texto"
  | "tipo_resposta"
  | "unidade"
  | "limite_min"
  | "limite_max"
  | "booleano_conforme"
  | "obrigatorio"
>;

/**
 * Estrutura de uma checklist devolvida por obter_checklists_kiosk().
 * Espelha o json_build_object da RPC (migração 20260713210000).
 */
export type ChecklistKiosk = {
  template_id: string;
  nome: string;
  versao_id: string;
  numero: number;
  frequencia_tipo: string;
  itens: ItemChecklist[];
};

/** Resultado da avaliação local de conformidade. */
export type ResultadoConformidade = {
  conforme: boolean;
  motivo: string | null;
};

// ---------------------------------------------------------------------------
// Helper de normalização
// ---------------------------------------------------------------------------

/**
 * Normaliza um valor numérico recebido do teclado do kiosk:
 * substitui a vírgula decimal por ponto, para que o Postgres possa
 * interpretar o valor como numeric (Postgres NÃO aceita vírgula).
 *
 * Deve ser aplicado ANTES de chamar avaliarConformidade com tipo 'numerico'
 * E ANTES de submeter o payload ao servidor em p_respostas.
 */
export function normalizarValorNumerico(valor: string): string {
  return valor.replace(",", ".");
}

// ---------------------------------------------------------------------------
// Avaliação de conformidade
// ---------------------------------------------------------------------------

/**
 * Avalia localmente a conformidade de uma resposta a um item de checklist.
 *
 * Porta fiel dos 4 braços da função SQL avaliar_conformidade (R2b):
 *   · numerico  : valor null/vazio/não-numérico → ilegível; verifica limites.
 *   · booleano  : 'true'/'false' → compara com booleano_conforme (padrão true).
 *   · texto     : se obrigatório → trim não vazio.
 *   · foto      : conforme ⇔ fotoUrl presente e não vazia.
 *
 * Para itens numéricos, o valor deve já estar normalizado (vírgula → ponto)
 * antes de chamar esta função — usa normalizarValorNumerico primeiro.
 *
 * @param item     Item da checklist (tipo e limites)
 * @param valor    Valor introduzido pelo colaborador (string ou null/vazio)
 * @param fotoUrl  URL da foto anexa (só relevante para tipo 'foto')
 */
export function avaliarConformidade(
  item: ItemChecklist,
  valor: string | null | undefined,
  fotoUrl?: string | null,
): ResultadoConformidade {
  switch (item.tipo_resposta) {
    case "numerico": {
      // NULL, vazio ou não-numérico → ilegível (espelha o begin/exception do SQL)
      if (valor == null || valor.trim() === "") {
        return { conforme: false, motivo: "valor ilegível" };
      }
      const num = Number(valor);
      if (!Number.isFinite(num) || valor.trim() === "") {
        return { conforme: false, motivo: "valor ilegível" };
      }
      // conforme ⇔ dentro dos limites (null = sem limite desse lado)
      const acimaDaMin = item.limite_min == null || num >= item.limite_min;
      const abaixoDaMax = item.limite_max == null || num <= item.limite_max;
      if (acimaDaMin && abaixoDaMax) {
        return { conforme: true, motivo: null };
      }
      // identifica o limite violado (mesma prioridade do SQL: max antes de min)
      if (item.limite_max != null && num > item.limite_max) {
        return {
          conforme: false,
          motivo: `valor ${num} acima do limite máximo ${item.limite_max}`,
        };
      }
      return {
        conforme: false,
        motivo: `valor ${num} abaixo do limite mínimo ${item.limite_min}`,
      };
    }

    case "booleano": {
      // NULL ou vazio → ilegível
      if (valor == null || valor.trim() === "") {
        return { conforme: false, motivo: "valor ilegível" };
      }
      // O kiosk envia 'true' ou 'false' (strings); outros valores → ilegível
      if (valor !== "true" && valor !== "false") {
        return { conforme: false, motivo: "valor ilegível" };
      }
      const v = valor === "true";
      const esperado = item.booleano_conforme ?? true;
      if (v === esperado) {
        return { conforme: true, motivo: null };
      }
      return {
        conforme: false,
        motivo: `resposta "${valor}" não conforme (esperado: ${esperado})`,
      };
    }

    case "texto": {
      // conforme ⇔ se obrigatório então valor não nulo e não vazio (trim)
      if (item.obrigatorio && (valor == null || valor.trim() === "")) {
        return { conforme: false, motivo: "resposta obrigatória em falta" };
      }
      return { conforme: true, motivo: null };
    }

    case "foto": {
      // conforme ⇔ fotoUrl presente e não vazia
      if (fotoUrl == null || fotoUrl.trim() === "") {
        return { conforme: false, motivo: "fotografia obrigatória em falta" };
      }
      return { conforme: true, motivo: null };
    }

    default:
      // Tipo desconhecido — não conforme por segurança
      return {
        conforme: false,
        motivo: `tipo de resposta desconhecido: ${item.tipo_resposta}`,
      };
  }
}
