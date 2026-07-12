// PicagemScreen.tsx
// Kiosk — fluxo: código -> PIN -> tipo -> foto -> picagem enfileirada.
//
// Sprint 3a: a captura escreve numa FILA local (outbox) e mostra ✓ assim que o
// item está duravelmente guardado — não espera pelo servidor.
//
// Sprint 3b: se a rede estiver em baixo no momento do PIN, valida o PIN
// LOCALMENTE (HMAC contra a cache) e deixa picar offline. A picagem entra na
// fila como "autorizada offline"; o servidor re-valida no drain. A UI é honesta:
// uma picagem offline aparece como "por confirmar", nunca como confirmada.
//
// Opções válidas offline: o ecrã calcula o estado real de hoje juntando o último
// estado vindo do servidor (cache) com a última picagem local ainda por enviar,
// e mostra só os tipos válidos — tal como online.
//
// Dependências: expo-camera, expo-crypto, base64-arraybuffer, expo-sqlite,
//   expo-secure-store (3b, nativo), @noble/hashes (3b, JS).

import React, { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  AppState,
  Dimensions,
  Image,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { CameraView, useCameraPermissions } from "expo-camera";
import * as Crypto from "expo-crypto";
import { supabase } from "./lib/supabase";
import {
  enfileirarOnline,
  enfileirarOffline,
  drenar,
  contarPendentes,
  contarRecusados,
  ultimoPickLocalHoje,
} from "./lib/outbox";
import {
  validarPinOffline,
  temCache,
  refrescarCache,
  cacheExpirada,
} from "./lib/cache-pin";

// --- Marca CoreVero -----------------------------------------------------------
const TINTA = "#10202E";
const TEAL = "#16A37D";
const PAPEL = "#F7F6F2";
const CINZA = "#6B7C8C";

const CIRCULO = Math.min(Dimensions.get("window").width - 64, 320);

type Tipo = "entrada" | "saida" | "inicio_intervalo" | "fim_intervalo";

const LABEL: Record<Tipo, string> = {
  entrada: "Entrada",
  saida: "Saída",
  inicio_intervalo: "Início de pausa",
  fim_intervalo: "Fim de pausa",
};

// Próximo tipo válido a partir da última picagem. Usado online E offline (offline
// a "última" é calculada da cache + picks locais).
function opcoesPara(ultima: Tipo | null): { sugerida: Tipo; opcoes: Tipo[] } {
  switch (ultima) {
    case "entrada":
    case "fim_intervalo":
      return { sugerida: "saida", opcoes: ["inicio_intervalo", "saida"] };
    case "inicio_intervalo":
      return { sugerida: "fim_intervalo", opcoes: ["fim_intervalo"] };
    case "saida":
    case null:
    default:
      return { sugerida: "entrada", opcoes: ["entrada"] };
  }
}

function horaLisboa(iso?: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("pt-PT", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Europe/Lisbon",
  });
}

// Erro de transporte (sem rede) vs erro do servidor (respondeu com um código).
function eErroDeRede(error: any): boolean {
  if (!error) return false;
  if (error.code) return false; // servidor respondeu -> não é rede
  return (
    /network|fetch|timeout|failed/i.test(String(error.message ?? "")) ||
    !error.code
  );
}

type Fase =
  | "codigo"
  | "pin"
  | "tipo"
  | "camera"
  | "processar"
  | "sucesso"
  | "erro";

export default function PicagemScreen({ lojaNome }: { lojaNome?: string }) {
  const [fase, setFase] = useState<Fase>("codigo");
  const [codigo, setCodigo] = useState("");
  const [pin, setPin] = useState("");
  const [nome, setNome] = useState("");
  const [offline, setOffline] = useState(false);
  const [autorizacaoId, setAutorizacaoId] = useState<string | null>(null);
  const [trabalhadorId, setTrabalhadorId] = useState<string | null>(null);
  const [ultimaTipo, setUltimaTipo] = useState<Tipo | null>(null);
  const [ultimaMomento, setUltimaMomento] = useState<string | null>(null);
  const [tipo, setTipo] = useState<Tipo | null>(null);
  const [erro, setErro] = useState("");
  const [sucessoTxt, setSucessoTxt] = useState("");
  const [pendentes, setPendentes] = useState(0);
  const [recusados, setRecusados] = useState(0);

  const [perm, requestPerm] = useCameraPermissions();
  const cameraRef = useRef<CameraView>(null);
  const emCurso = useRef(false);

  // Sincronizar: refresca a cache (se houver rede), drena a fila, atualiza contadores.
  async function sincronizar() {
    try {
      await refrescarCache();
    } catch {
      /* offline ou erro: silêncio */
    }
    await drenar();
    setPendentes(await contarPendentes());
    setRecusados(await contarRecusados());
  }
  useEffect(() => {
    sincronizar();
    const sub = AppState.addEventListener("change", (st) => {
      if (st === "active") sincronizar();
    });
    const iv = setInterval(sincronizar, 15000);
    return () => {
      sub.remove();
      clearInterval(iv);
    };
  }, []);

  useEffect(() => {
    if (fase === "sucesso" || fase === "erro") {
      const t = setTimeout(reset, fase === "sucesso" ? 3500 : 4000);
      return () => clearTimeout(t);
    }
  }, [fase]);

  function reset() {
    setCodigo("");
    setPin("");
    setNome("");
    setOffline(false);
    setAutorizacaoId(null);
    setTrabalhadorId(null);
    setUltimaTipo(null);
    setUltimaMomento(null);
    setTipo(null);
    setErro("");
    setSucessoTxt("");
    emCurso.current = false;
    setFase("codigo");
  }

  function falhar(msg: string) {
    setErro(msg);
    emCurso.current = false;
    setFase("erro");
  }

  function premirTecla(d: string) {
    if (fase === "codigo") setCodigo((s) => (s.length < 8 ? s + d : s));
    else if (fase === "pin") setPin((s) => (s.length < 8 ? s + d : s));
  }
  function apagar() {
    if (fase === "codigo") setCodigo((s) => s.slice(0, -1));
    else if (fase === "pin") setPin((s) => s.slice(0, -1));
  }

  function avancarParaPin() {
    if (codigo.trim().length === 0) return;
    setFase("pin");
  }

  // PASSO 2: validar PIN. Online via servidor; se a rede falhar, valida offline.
  async function validarPin() {
    if (emCurso.current) return;
    if (pin.trim().length === 0) return;
    emCurso.current = true;
    setFase("processar");

    let data: any = null;
    let error: any = null;
    try {
      ({ data, error } = await supabase.rpc("iniciar_picagem", {
        p_codigo_pessoal: codigo.trim(),
        p_pin: pin.trim(),
      }));
    } catch (e) {
      error = e; // exceção de transporte (sem rede)
    }
    emCurso.current = false;

    // ONLINE — servidor validou e emitiu bilhete.
    if (!error && data) {
      setOffline(false);
      setNome(data.nome ?? "");
      setTrabalhadorId(data.trabalhador_id ?? null);
      setAutorizacaoId(data.autorizacao_id ?? null);
      setUltimaTipo((data.ultima_tipo as Tipo) ?? null);
      setUltimaMomento(data.ultima_momento ?? null);
      setTipo(opcoesPara((data.ultima_tipo as Tipo) ?? null).sugerida);
      setFase("tipo");
      return;
    }

    // Servidor RESPONDEU com erro (não é rede) -> PIN inválido ou revogado.
    if (!eErroDeRede(error)) {
      const msg = error?.message ?? "";
      if (/revogad/i.test(msg)) {
        return falhar("Este dispositivo foi revogado. Contacte o gestor.");
      }
      return falhar("Código ou PIN inválido.");
    }

    // OFFLINE — validar contra a cache local.
    const t = await validarPinOffline(codigo.trim(), pin.trim());
    if (!t) {
      if (await cacheExpirada()) {
        return falhar(
          "Sem ligação e os dados locais expiraram. Ligue à rede para atualizar.",
        );
      }
      const cache = await temCache();
      return falhar(
        cache
          ? "Sem ligação. Código ou PIN inválido."
          : "Sem ligação e sem dados para validar offline. Tente quando houver rede.",
      );
    }
    setOffline(true);
    setNome(t.nome);
    setTrabalhadorId(t.trabalhador_id);
    setAutorizacaoId(null);

    // Estado real de HOJE = o mais recente entre o último do servidor (cache, se
    // for de hoje) e a última picagem local ainda por enviar (de hoje).
    const hoje = new Date().toLocaleDateString("en-CA", {
      timeZone: "Europe/Lisbon",
    });
    const cacheHoje =
      t.ultimo_momento &&
      new Date(t.ultimo_momento).toLocaleDateString("en-CA", {
        timeZone: "Europe/Lisbon",
      }) === hoje
        ? { tipo: t.ultimo_tipo as Tipo, momento: t.ultimo_momento }
        : null;
    const local = await ultimoPickLocalHoje(t.trabalhador_id);
    let efetiva = cacheHoje;
    if (local && (!efetiva || local.momento > efetiva.momento)) {
      efetiva = { tipo: local.tipo as Tipo, momento: local.momento };
    }

    setUltimaTipo(efetiva?.tipo ?? null);
    setUltimaMomento(efetiva?.momento ?? null);
    setTipo(opcoesPara(efetiva?.tipo ?? null).sugerida);
    setFase("tipo");
  }

  // Opções de tipo válidas — calculadas da última picagem (online ou offline).
  function opcoesEcra(): Tipo[] {
    return opcoesPara(ultimaTipo).opcoes;
  }

  async function escolherTipo(t: Tipo) {
    setTipo(t);
    if (!perm?.granted) {
      const r = await requestPerm();
      if (!r.granted) return falhar("Sem permissão de câmara.");
    }
    setFase("camera");
  }

  // PASSO 4: capturar foto -> enfileirar (online com bilhete, offline com trabalhador).
  async function capturarERegistar() {
    if (emCurso.current || !cameraRef.current || !tipo) return;
    if (offline ? !trabalhadorId : !autorizacaoId) return;
    emCurso.current = true;
    setFase("processar");

    const momento = new Date().toISOString(); // hora autoritária = toque
    const chave = Crypto.randomUUID(); // chave de idempotência

    let base64: string | undefined;
    try {
      const foto = await cameraRef.current.takePictureAsync({
        quality: 0.5,
        base64: true,
      });
      base64 = foto?.base64;
    } catch {
      return falhar("Falha ao capturar a foto.");
    }
    if (!base64) return falhar("Falha ao capturar a foto.");

    try {
      if (offline) {
        await enfileirarOffline({
          id: chave,
          trabalhador_id: trabalhadorId!,
          codigo_pessoal: codigo.trim(),
          tipo,
          momento,
          foto_b64: base64,
        });
      } else {
        await enfileirarOnline({
          id: chave,
          autorizacao_id: autorizacaoId!,
          trabalhador_id: trabalhadorId ?? "",
          codigo_pessoal: codigo.trim(),
          tipo,
          momento,
          foto_b64: base64,
        });
      }
    } catch {
      return falhar("Falha ao guardar a picagem no dispositivo.");
    }

    emCurso.current = false;
    setSucessoTxt(
      offline
        ? `${LABEL[tipo]} registada offline às ${horaLisboa(momento)} · por confirmar`
        : `${LABEL[tipo]} registada às ${horaLisboa(momento)}`,
    );
    setFase("sucesso");
    sincronizar();
  }

  // --- RENDER -----------------------------------------------------------------
  return (
    <View style={s.root}>
      {lojaNome && fase !== "camera" && fase !== "sucesso" ? (
        <Text style={s.lojaLabel}>{lojaNome}</Text>
      ) : null}

      {(pendentes > 0 || recusados > 0) &&
      fase !== "camera" &&
      fase !== "sucesso" ? (
        <View style={s.avisos}>
          {pendentes > 0 ? (
            <View style={s.pendentes}>
              <Text style={s.pendentesTxt}>
                {pendentes}{" "}
                {pendentes === 1 ? "picagem por enviar" : "picagens por enviar"}
              </Text>
            </View>
          ) : null}
          {recusados > 0 ? (
            <View style={s.recusados}>
              <Text style={s.recusadosTxt}>
                {recusados} {recusados === 1 ? "recusada" : "recusadas"} —
                contacte o gestor
              </Text>
            </View>
          ) : null}
        </View>
      ) : null}

      {fase === "codigo" && (
        <Keypad
          titulo="Código do colaborador"
          valor={codigo}
          mascarar={false}
          onTecla={premirTecla}
          onApagar={apagar}
          acaoLabel="Continuar"
          acaoAtiva={codigo.length > 0}
          onAcao={avancarParaPin}
        />
      )}

      {fase === "pin" && (
        <Keypad
          titulo="PIN"
          valor={pin}
          mascarar
          onTecla={premirTecla}
          onApagar={apagar}
          acaoLabel="Validar"
          acaoAtiva={pin.length > 0}
          onAcao={validarPin}
          onVoltar={() => {
            setPin("");
            setFase("codigo");
          }}
        />
      )}

      {fase === "tipo" && tipo && (
        <View style={s.centro}>
          <Text style={s.ola}>Olá, {nome}</Text>
          {ultimaTipo ? (
            <Text style={[s.sub, offline ? { color: "#9A6A1E" } : null]}>
              {offline ? "Sem ligação · " : ""}Última: {LABEL[ultimaTipo]} às{" "}
              {horaLisboa(ultimaMomento)}
            </Text>
          ) : (
            <Text style={[s.sub, offline ? { color: "#9A6A1E" } : null]}>
              {offline ? "Sem ligação · " : ""}Sem picagens hoje
            </Text>
          )}
          <View style={s.tipos}>
            {opcoesEcra().map((t) => (
              <Pressable
                key={t}
                style={[s.tipoBtn, tipo === t && s.tipoBtnSel]}
                onPress={() => escolherTipo(t)}
              >
                <Text style={[s.tipoTxt, tipo === t && s.tipoTxtSel]}>
                  {LABEL[t]}
                </Text>
              </Pressable>
            ))}
          </View>
          <Pressable style={s.link} onPress={reset}>
            <Text style={s.linkTxt}>Cancelar</Text>
          </Pressable>
        </View>
      )}

      {fase === "camera" && (
        <View style={s.cameraWrap}>
          <Text style={s.cameraTitulo}>
            {nome}
            {tipo ? ` · ${LABEL[tipo]}` : ""}
            {offline ? " · offline" : ""}
          </Text>

          <View style={s.circulo}>
            <CameraView
              ref={cameraRef}
              style={StyleSheet.absoluteFill}
              facing="front"
            />
          </View>

          <Image
            source={require("./assets/wordmark-papel.png")}
            style={s.wordmark}
            resizeMode="contain"
          />

          <Pressable style={s.shutter} onPress={capturarERegistar}>
            <Text style={s.shutterTxt}>Confirmar picagem</Text>
          </Pressable>
          <Pressable style={s.link} onPress={reset}>
            <Text style={[s.linkTxt, { color: CINZA }]}>Cancelar</Text>
          </Pressable>
        </View>
      )}

      {fase === "processar" && (
        <View style={s.centro}>
          <ActivityIndicator size="large" color={TEAL} />
          <Text style={s.sub}>A processar…</Text>
        </View>
      )}

      {fase === "sucesso" && (
        <View
          style={[s.centro, { backgroundColor: offline ? "#9A6A1E" : TINTA }]}
        >
          {offline ? (
            <Text style={s.bigCheck}>⏳</Text>
          ) : (
            <Image
              source={require("./assets/check-papel.png")}
              style={s.checkLogo}
              resizeMode="contain"
            />
          )}
          <Text style={s.sucesso}>{sucessoTxt}</Text>
        </View>
      )}

      {fase === "erro" && (
        <View style={s.centro}>
          <Text style={s.erro}>{erro}</Text>
          <Pressable style={s.tipoBtn} onPress={reset}>
            <Text style={s.tipoTxt}>Recomeçar</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

// --- Teclado numérico ---------------------------------------------------------
function Keypad(props: {
  titulo: string;
  valor: string;
  mascarar: boolean;
  onTecla: (d: string) => void;
  onApagar: () => void;
  acaoLabel: string;
  acaoAtiva: boolean;
  onAcao: () => void;
  onVoltar?: () => void;
}) {
  const mostrado = props.mascarar
    ? "•".repeat(props.valor.length)
    : props.valor;
  return (
    <View style={s.centro}>
      <Text style={s.titulo}>{props.titulo}</Text>
      <Text style={s.visor}>{mostrado || " "}</Text>
      <View style={s.grid}>
        {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((d) => (
          <Pressable key={d} style={s.tecla} onPress={() => props.onTecla(d)}>
            <Text style={s.teclaTxt}>{d}</Text>
          </Pressable>
        ))}
        <Pressable style={s.tecla} onPress={props.onApagar}>
          <Text style={s.teclaTxt}>⌫</Text>
        </Pressable>
        <Pressable style={s.tecla} onPress={() => props.onTecla("0")}>
          <Text style={s.teclaTxt}>0</Text>
        </Pressable>
        <Pressable
          style={[s.tecla, s.teclaOk, !props.acaoAtiva && s.teclaOff]}
          onPress={props.acaoAtiva ? props.onAcao : undefined}
        >
          <Text style={[s.teclaTxt, { color: PAPEL }]}>↵</Text>
        </Pressable>
      </View>
      <Pressable
        style={[s.acao, !props.acaoAtiva && s.teclaOff]}
        onPress={props.acaoAtiva ? props.onAcao : undefined}
      >
        <Text style={s.acaoTxt}>{props.acaoLabel}</Text>
      </Pressable>
      {props.onVoltar && (
        <Pressable style={s.link} onPress={props.onVoltar}>
          <Text style={s.linkTxt}>Voltar</Text>
        </Pressable>
      )}
    </View>
  );
}

// --- Estilos ------------------------------------------------------------------
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: PAPEL },
  lojaLabel: {
    position: "absolute",
    top: 52,
    alignSelf: "center",
    fontSize: 13,
    color: CINZA,
    fontWeight: "600",
    zIndex: 10,
  },
  avisos: {
    position: "absolute",
    top: 78,
    alignSelf: "center",
    gap: 6,
    alignItems: "center",
    zIndex: 10,
  },
  pendentes: {
    backgroundColor: "#E9A23B22",
    borderColor: "#E9A23B",
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 4,
  },
  pendentesTxt: { fontSize: 12, color: "#9A6A1E", fontWeight: "700" },
  recusados: {
    backgroundColor: "#B23A3A18",
    borderColor: "#B23A3A",
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 4,
  },
  recusadosTxt: { fontSize: 12, color: "#B23A3A", fontWeight: "700" },
  centro: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },

  titulo: { fontSize: 22, color: TINTA, marginBottom: 12, fontWeight: "600" },
  visor: {
    fontSize: 44,
    color: TINTA,
    letterSpacing: 6,
    minHeight: 60,
    fontWeight: "700",
  },

  grid: {
    width: 300,
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "space-between",
    marginTop: 16,
  },
  tecla: {
    width: 92,
    height: 72,
    marginVertical: 6,
    borderRadius: 14,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#FFFFFF",
    borderWidth: 1,
    borderColor: "#E3E1DA",
  },
  teclaOk: { backgroundColor: TEAL, borderColor: TEAL },
  teclaOff: { opacity: 0.4 },
  teclaTxt: { fontSize: 26, color: TINTA, fontWeight: "600" },

  acao: {
    marginTop: 18,
    backgroundColor: TINTA,
    paddingVertical: 16,
    paddingHorizontal: 48,
    borderRadius: 14,
  },
  acaoTxt: { color: PAPEL, fontSize: 18, fontWeight: "700" },

  ola: { fontSize: 28, color: TINTA, fontWeight: "700" },
  sub: { fontSize: 16, color: CINZA, marginTop: 6 },

  tipos: { marginTop: 28, width: "100%", maxWidth: 420, gap: 12 },
  tipoBtn: {
    paddingVertical: 18,
    borderRadius: 14,
    backgroundColor: "#FFFFFF",
    borderWidth: 1,
    borderColor: "#E3E1DA",
    alignItems: "center",
  },
  tipoBtnSel: { backgroundColor: TINTA, borderColor: TINTA },
  tipoTxt: { fontSize: 20, color: TINTA, fontWeight: "600" },
  tipoTxtSel: { color: PAPEL },

  cameraWrap: {
    flex: 1,
    backgroundColor: TINTA,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  cameraTitulo: {
    color: PAPEL,
    fontSize: 22,
    fontWeight: "700",
    marginBottom: 28,
    textAlign: "center",
  },
  circulo: {
    width: CIRCULO,
    height: CIRCULO,
    borderRadius: CIRCULO / 2,
    overflow: "hidden",
    backgroundColor: "#000",
    borderWidth: 3,
    borderColor: TEAL,
  },
  wordmark: {
    width: 180,
    height: 44,
    marginTop: 28,
    marginBottom: 8,
    opacity: 0.95,
  },
  shutter: {
    backgroundColor: TEAL,
    paddingVertical: 18,
    paddingHorizontal: 40,
    borderRadius: 16,
    marginTop: 16,
  },
  shutterTxt: { color: PAPEL, fontSize: 20, fontWeight: "700" },

  bigCheck: { fontSize: 96, color: PAPEL, fontWeight: "900" },
  checkLogo: { width: 170, height: 160, marginBottom: 8 },
  sucesso: {
    fontSize: 22,
    color: PAPEL,
    fontWeight: "700",
    marginTop: 8,
    textAlign: "center",
  },

  erro: {
    fontSize: 20,
    color: "#B23A3A",
    fontWeight: "600",
    marginBottom: 20,
    textAlign: "center",
  },

  link: { marginTop: 22 },
  linkTxt: { fontSize: 15, color: CINZA, textDecorationLine: "underline" },
});
