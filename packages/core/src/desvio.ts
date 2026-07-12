// Limiar de sinalização do desvio entre a hora do dispositivo e a hora do servidor.
// TODO: mover para configuração por empresa quando a tabela existir (âmbito do R3).
export const LIMIAR_DESVIO_SEGUNDOS = 300;

/**
 * Formata o desvio de relógio do dispositivo para apresentar num tooltip.
 *
 * Semântica: desvio_segundos = momento_servidor − momento_dispositivo.
 * Valor positivo → servidor à frente → relógio do dispositivo atrasado.
 * O tooltip mostra a perspetiva do dispositivo (inverter o sinal):
 *   desvio_segundos = +420 → dispositivo está 7 min atrás  → "−7 min vs servidor"
 *   desvio_segundos = −120 → dispositivo está 2 min à frente → "+2 min vs servidor"
 * Devolve null quando desvio_segundos é null.
 * Arredonda a minutos quando abs ≥ 60 s; caso contrário mostra em segundos.
 */
export function formatarDesvio(desvio_segundos: number | null): string | null {
  if (desvio_segundos === null) return null;
  // Perspetiva do dispositivo: o sinal inverte-se relativamente a desvio_segundos.
  const perspetiva = -desvio_segundos;
  const abs = Math.abs(perspetiva);
  const sinal = perspetiva >= 0 ? "+" : "−";
  if (abs >= 60) {
    const mins = Math.round(abs / 60);
    return `${sinal}${mins} min vs servidor`;
  }
  return `${sinal}${abs} s vs servidor`;
}
