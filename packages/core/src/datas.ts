// Helpers de datas fixos em Europe/Lisbon, partilhados por admin e kiosk.
// A hora "de parede" é a que o utilizador vê num relógio em Lisboa; a conversão
// para UTC tem de atravessar o DST corretamente (WET/WEST), sem depender do
// fuso do browser/dispositivo.

/**
 * Converte (data "YYYY-MM-DD" + hora "HH:MM" de parede de Lisboa) para um
 * instante ISO UTC correto, com DST.
 */
export function paredeParaUTC(data: string, hora: string): string {
  const naive = new Date(`${data}T${hora}:00Z`);
  const lis = new Date(naive.toLocaleString("en-US", { timeZone: "Europe/Lisbon" }));
  const utc = new Date(naive.toLocaleString("en-US", { timeZone: "UTC" }));
  return new Date(naive.getTime() - (lis.getTime() - utc.getTime())).toISOString();
}
