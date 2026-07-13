// ChecklistsScreen.tsx
// Kiosk — fluxo de preenchimento de checklists HACCP.
//
// Online-only (doc 13 D5): sem rede não é possível iniciar nem submeter.
// A avaliação de conformidade é local (UX apenas); a autoridade é sempre o
// servidor (registar_checklist valida e avalia de raiz — D3 do doc 13).
//
// Fases:
//   lista      → lista de checklists disponíveis (carregadas de cache + servidor)
//   codigo     → pede o código pessoal do colaborador (Keypad)
//   pin        → pede o PIN (Keypad mascarado)
//   camera     → captura foto de atribuição frontal (mesmo padrão da picagem)
//   formulario → preenchimento item a item (scroll view)
//   processar  → a submeter ao servidor
//   sucesso    → confirmação com resumo; auto-reset
//   erro       → texto COMPLETO do erro (nunca engolir)

import React, { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  AppState,
  Dimensions,
  Image,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { CameraView, useCameraPermissions } from "expo-camera";
import { decode } from "base64-arraybuffer";
import {
  avaliarConformidade,
  normalizarValorNumerico,
} from "@corevero/core";
import type { ChecklistKiosk, ItemChecklist } from "@corevero/core";
import { supabase } from "./lib/supabase";
import {
  obterChecklistsCache,
  guardarChecklistsCache,
  checklistsCacheRecente,
} from "./lib/cache-checklists";

// ---------------------------------------------------------------------------
// Paleta (mesma da PicagemScreen)
// ---------------------------------------------------------------------------
const TINTA = "#10202E";
const TEAL = "#16A37D";
const PAPEL = "#F7F6F2";
const CINZA = "#6B7C8C";
const VERMELHO = "#B23A3A";

const CIRCULO = Math.min(Dimensions.get("window").width - 64, 320);

// ---------------------------------------------------------------------------
// Tipos locais
// ---------------------------------------------------------------------------
type FaseChecklists =
  | "lista"
  | "codigo"
  | "pin"
  | "camera"
  | "formulario"
  | "processar"
  | "sucesso"
  | "erro";

// Erro de transporte (sem rede) vs. erro do servidor (respondeu com um código).
function eErroDeRede(error: unknown): boolean {
  if (!error) return false;
  const e = error as Record<string, unknown>;
  if (e["code"]) return false; // servidor respondeu → não é rede
  return /network|fetch|timeout|failed/i.test(String(e["message"] ?? ""));
}

// ---------------------------------------------------------------------------
// Componente
// ---------------------------------------------------------------------------
export default function ChecklistsScreen({
  lojaNome,
}: {
  lojaNome?: string;
}) {
  // --- Fase -----------------------------------------------------------------
  const [fase, setFase] = useState<FaseChecklists>("lista");

  // --- Lista ----------------------------------------------------------------
  const [checklists, setChecklists] = useState<ChecklistKiosk[]>([]);
  const [estaOnline, setEstaOnline] = useState<boolean | null>(null); // null = a verificar
  const [aCarregar, setACarregar] = useState(false);

  // --- Checklist seleccionada -----------------------------------------------
  const [checklistSel, setChecklistSel] = useState<ChecklistKiosk | null>(null);

  // --- Autenticação ---------------------------------------------------------
  const [codigo, setCodigo] = useState("");
  const [pin, setPin] = useState("");

  // --- Câmara ---------------------------------------------------------------
  const [perm, requestPerm] = useCameraPermissions();
  const cameraRef = useRef<CameraView>(null);
  const [fotoBase64, setFotoBase64] = useState<string | null>(null);

  // --- Formulário -----------------------------------------------------------
  // momento carimbado ao entrar no formulário (após auth + foto)
  const [momentoDispositivo, setMomentoDispositivo] = useState("");
  // respostas: itemId → valor (string; numéricos já normalizados)
  const [respostas, setRespostas] = useState<Record<string, string>>({});
  // acoes corretivas: itemId → descrição
  const [acoes, setAcoes] = useState<Record<string, string>>({});
  // item activo no teclado numérico (bottom panel)
  const [itemNumericoAtivo, setItemNumericoAtivo] = useState<string | null>(null);

  // --- Resultado ------------------------------------------------------------
  const [resumoSucesso, setResumoSucesso] = useState<{
    respostas: number;
    naoConformes: number;
    acoes: number;
  } | null>(null);
  const [textoErro, setTextoErro] = useState("");
  // Aviso de upload de foto: o registo já persistiu no servidor, mas a foto
  // de atribuição não chegou ao bucket. Visível no ecrã de sucesso (regra
  // "erros nunca são engolidos" — CLAUDE.md).
  const [avisoFoto, setAvisoFoto] = useState<string | null>(null);

  const emCurso = useRef(false);

  // --- Carregar checklists --------------------------------------------------
  async function carregarChecklists(forcar = false): Promise<void> {
    // Carrega da cache imediatamente para mostrar a lista sem esperar pela rede
    const cache = await obterChecklistsCache();
    if (cache.length > 0) setChecklists(cache);

    // Throttle: se o cache é recente e não forçado, não bate no servidor
    if (!forcar && checklistsCacheRecente() && cache.length > 0) return;

    setACarregar(true);
    try {
      const { data, error } = await supabase.rpc("obter_checklists_kiosk");
      if (error) {
        if (eErroDeRede(error)) {
          setEstaOnline(false);
        } else {
          // Erro do servidor (kiosk revogado, etc.) — mostra mas não desliga online
          setEstaOnline(true);
          setTextoErro(error.message ?? String(error));
          setFase("erro");
        }
        return;
      }
      const lista = (data as ChecklistKiosk[]) ?? [];
      setChecklists(lista);
      await guardarChecklistsCache(lista);
      setEstaOnline(true);
    } catch (e: unknown) {
      setEstaOnline(false);
    } finally {
      setACarregar(false);
    }
  }

  useEffect(() => {
    carregarChecklists();
    const sub = AppState.addEventListener("change", (st) => {
      if (st === "active") carregarChecklists();
    });
    const iv = setInterval(() => carregarChecklists(), 15000);
    return () => {
      sub.remove();
      clearInterval(iv);
    };
  }, []);

  // Auto-reset nos ecrãs terminais
  useEffect(() => {
    if (fase === "sucesso" || fase === "erro") {
      const t = setTimeout(reset, fase === "sucesso" ? 3500 : 5000);
      return () => clearTimeout(t);
    }
  }, [fase]);

  // --- Reset ----------------------------------------------------------------
  function reset() {
    setCodigo("");
    setPin("");
    setFotoBase64(null);
    setChecklistSel(null);
    setMomentoDispositivo("");
    setRespostas({});
    setAcoes({});
    setItemNumericoAtivo(null);
    setResumoSucesso(null);
    setTextoErro("");
    setAvisoFoto(null);
    emCurso.current = false;
    setFase("lista");
  }

  function falhar(msg: string) {
    setTextoErro(msg);
    emCurso.current = false;
    setFase("erro");
  }

  // --- Seleccionar checklist ------------------------------------------------
  function selecionarChecklist(c: ChecklistKiosk) {
    if (!estaOnline) return; // online-only: não deixa iniciar sem rede
    setChecklistSel(c);
    setRespostas({});
    setAcoes({});
    setFase("codigo");
  }

  // --- Keypad (código / PIN) ------------------------------------------------
  function premirTeclaAuth(d: string) {
    if (fase === "codigo") setCodigo((s) => (s.length < 8 ? s + d : s));
    else if (fase === "pin") setPin((s) => (s.length < 8 ? s + d : s));
  }
  function apagarAuth() {
    if (fase === "codigo") setCodigo((s) => s.slice(0, -1));
    else if (fase === "pin") setPin((s) => s.slice(0, -1));
  }

  async function avancarParaPin() {
    if (codigo.trim().length === 0) return;
    setFase("pin");
  }

  async function avancarParaCamera() {
    if (pin.trim().length === 0) return;
    // Validação de formato apenas; a validação real é server-side no submit
    if (!perm?.granted) {
      const r = await requestPerm();
      if (!r.granted) return falhar("Sem permissão de câmara.");
    }
    setFase("camera");
  }

  // --- Câmara ---------------------------------------------------------------
  async function capturarFoto() {
    if (emCurso.current || !cameraRef.current) return;
    emCurso.current = true;

    let base64: string | undefined;
    try {
      const foto = await cameraRef.current.takePictureAsync({
        quality: 0.5,
        base64: true,
      });
      base64 = foto?.base64;
    } catch {
      emCurso.current = false;
      return falhar("Falha ao capturar a foto.");
    }
    if (!base64) {
      emCurso.current = false;
      return falhar("Falha ao capturar a foto.");
    }

    setFotoBase64(base64);
    // momento_dispositivo carimbado ao entrar no formulário (após auth + foto)
    setMomentoDispositivo(new Date().toISOString());
    emCurso.current = false;
    setFase("formulario");
  }

  // --- Keypad numérico (formulário) ----------------------------------------
  function premirTeclaNumerico(itemId: string, tecla: string) {
    setRespostas((prev) => {
      const atual = prev[itemId] ?? "";
      // Vígula só pode aparecer uma vez
      if (tecla === "," && atual.includes(",")) return prev;
      if (tecla === "," && atual.includes(".")) return prev;
      return { ...prev, [itemId]: atual + tecla };
    });
  }
  function apagarNumerico(itemId: string) {
    setRespostas((prev) => {
      const atual = prev[itemId] ?? "";
      return { ...prev, [itemId]: atual.slice(0, -1) };
    });
  }

  // --- Avaliação local por item --------------------------------------------
  function avaliarItem(
    item: ItemChecklist,
  ): { conforme: boolean; motivo: string | null } {
    const valorBruto = respostas[item.id] ?? "";
    const valor =
      item.tipo_resposta === "numerico"
        ? normalizarValorNumerico(valorBruto)
        : valorBruto;
    return avaliarConformidade(item, valor || null);
  }

  // --- Condição de submit --------------------------------------------------
  function podeSubmeter(): boolean {
    if (!checklistSel) return false;
    const itensFiltrados = checklistSel.itens.filter(
      (i) => i.tipo_resposta !== "foto",
    );
    for (const item of itensFiltrados) {
      const v = respostas[item.id] ?? "";

      // Item obrigatório sem resposta → bloqueia
      if (item.obrigatorio && v.trim() === "") return false;

      // Só avalia conformidade para itens COM resposta (itens sem resposta
      // não serão enviados se não forem obrigatórios; nunca mostramos ação
      // para itens sem resposta, por isso não podemos bloquear aqui)
      if (v.trim() !== "") {
        const { conforme } = avaliarItem(item);
        if (!conforme) {
          const acao = (acoes[item.id] ?? "").trim();
          if (acao === "") return false;
        }
      }
    }
    return true;
  }

  // --- Submeter checklist --------------------------------------------------
  async function submeterChecklist() {
    if (emCurso.current || !checklistSel || !fotoBase64) return;
    if (!estaOnline) {
      return falhar(
        "Sem ligação. Não é possível submeter uma checklist sem rede.",
      );
    }
    emCurso.current = true;
    setFase("processar");

    // Construir payload de respostas (excluir itens foto não suportados).
    // Regra: incluir itens COM resposta + itens obrigatórios SEM resposta (para
    // que o servidor devolva o erro correcto em vez de silêncio).
    const itensSuportados = checklistSel.itens.filter(
      (i) => i.tipo_resposta !== "foto",
    );

    const payloadRespostas = itensSuportados
      .filter((i) => {
        const v = respostas[i.id] ?? "";
        // Inclui se tem resposta OU se é obrigatório (deixa o servidor rejeitar
        // caso a validação local tenha falhado por algum motivo)
        return v.trim() !== "" || i.obrigatorio;
      })
      .map((item) => {
        const valorBruto = respostas[item.id] ?? "";
        const valor =
          item.tipo_resposta === "numerico"
            ? normalizarValorNumerico(valorBruto) || null
            : valorBruto || null;
        return {
          item_id: item.id,
          valor,
          foto_url: null,
        };
      });

    // Avaliação local para determinar não conformes — só para itens COM resposta
    // (itens sem resposta não estão no payload ou têm valor=null e o servidor trata)
    const ncItemIds = new Set<string>();
    for (const item of itensSuportados) {
      const valorBruto = respostas[item.id] ?? "";
      if (valorBruto.trim() === "") continue; // sem resposta → não avaliamos localmente
      const valor =
        item.tipo_resposta === "numerico"
          ? normalizarValorNumerico(valorBruto)
          : valorBruto;
      const { conforme } = avaliarConformidade(item, valor);
      if (!conforme) ncItemIds.add(item.id);
    }

    // Payload de acções (apenas para os não conformes localmente avaliados)
    const payloadAcoes = Array.from(ncItemIds)
      .filter((id) => (acoes[id] ?? "").trim() !== "")
      .map((id) => ({
        item_id: id,
        descricao: acoes[id]!.trim(),
      }));

    // Chamada ao servidor
    let data: Record<string, unknown> | null = null;
    let error: { message?: string } | null = null;
    try {
      const resp = await supabase.rpc("registar_checklist", {
        p_codigo_pessoal: codigo.trim(),
        p_pin: pin.trim(),
        p_versao_id: checklistSel.versao_id,
        p_momento_dispositivo: momentoDispositivo,
        p_respostas: payloadRespostas,
        p_acoes: payloadAcoes,
      });
      data = (resp.data as Record<string, unknown>) ?? null;
      error = resp.error as { message?: string } | null;
    } catch (e: unknown) {
      emCurso.current = false;
      const msg = (e as { message?: string })?.message ?? String(e);
      return falhar(msg);
    }

    if (error) {
      emCurso.current = false;
      // Nunca engolir: mostrar o texto COMPLETO do erro (pode ser multi-linha)
      return falhar(error.message ?? JSON.stringify(error));
    }
    if (!data) {
      emCurso.current = false;
      return falhar("Resposta inesperada do servidor (sem dados).");
    }

    const fotoPath = data["foto_path"] as string | null;

    // Upload da foto de atribuição ao bucket picagens.
    // Não abortar nem mostrar ecrã de erro — o registo já persistiu no servidor.
    // Em caso de falha, guardar em avisoFoto para mostrar no ecrã de sucesso
    // (regra "erros nunca são engolidos").
    if (fotoPath && fotoBase64) {
      try {
        const buffer = decode(fotoBase64);
        const { error: upErr } = await supabase.storage
          .from("picagens")
          .upload(fotoPath, buffer, {
            contentType: "image/jpeg",
            upsert: false,
          });
        if (upErr) {
          setAvisoFoto(
            `O registo foi guardado, mas a foto de atribuição não foi carregada: ${upErr.message}`,
          );
        }
      } catch (e: unknown) {
        const msg =
          (e as { message?: string })?.message ?? String(e);
        setAvisoFoto(
          `O registo foi guardado, mas a foto de atribuição não foi carregada: ${msg}`,
        );
      }
    }

    emCurso.current = false;
    setResumoSucesso({
      respostas: (data["respostas"] as number) ?? 0,
      naoConformes: (data["nao_conformes"] as number) ?? 0,
      acoes: (data["acoes"] as number) ?? 0,
    });
    setFase("sucesso");
    // Refresca a lista no fundo (a checklist pode ter mudado de estado)
    carregarChecklists(true);
  }

  // --- Texto dos limites numéricos -----------------------------------------
  function texteLimites(item: ItemChecklist): string {
    if (item.tipo_resposta !== "numerico") return "";
    const { limite_min: mn, limite_max: mx, unidade: u } = item;
    const un = u ? ` ${u}` : "";
    if (mn != null && mx != null) return `${mn}${un} – ${mx}${un}`;
    if (mx != null) return `≤ ${mx}${un}`;
    if (mn != null) return `≥ ${mn}${un}`;
    return "";
  }

  // --------------------------------------------------------------------------
  // RENDER
  // --------------------------------------------------------------------------
  return (
    <View style={s.root}>
      {/* Cabeçalho com nome da loja */}
      {lojaNome && fase !== "camera" && fase !== "sucesso" ? (
        <Text style={s.lojaLabel}>{lojaNome}</Text>
      ) : null}

      {/* ===== LISTA ===== */}
      {fase === "lista" && (
        <View style={s.root}>
          <Text style={s.tituloPainel}>Checklists HACCP</Text>

          {/* Estado da rede */}
          {estaOnline === false ? (
            <View style={s.offlineWrap}>
              <Text style={s.offlineTxt}>
                Checklists indisponíveis sem ligação
              </Text>
              <Text style={s.offlineSub}>
                Ligue o tablet à rede para preencher checklists.
              </Text>
              <Pressable
                style={s.btnTentar}
                onPress={() => carregarChecklists(true)}
              >
                <Text style={s.btnTentarTxt}>Tentar novamente</Text>
              </Pressable>
            </View>
          ) : (
            <ScrollView
              style={s.lista}
              contentContainerStyle={s.listaConteudo}
            >
              {estaOnline === null || aCarregar ? (
                <ActivityIndicator
                  color={TEAL}
                  style={{ marginTop: 40 }}
                />
              ) : checklists.length === 0 ? (
                <Text style={s.semChecklists}>
                  Nenhuma checklist publicada para esta loja.
                </Text>
              ) : (
                checklists.map((c) => (
                  <Pressable
                    key={c.versao_id}
                    style={s.checklistCard}
                    onPress={() => selecionarChecklist(c)}
                  >
                    <Text style={s.checklistNome}>{c.nome}</Text>
                    <Text style={s.checklistMeta}>
                      v{c.numero} · {c.itens.length}{" "}
                      {c.itens.length === 1 ? "item" : "itens"}
                    </Text>
                    <Text style={s.checklistIniciar}>Preencher →</Text>
                  </Pressable>
                ))
              )}
            </ScrollView>
          )}
        </View>
      )}

      {/* ===== CÓDIGO ===== */}
      {fase === "codigo" && (
        <KeypadAuth
          titulo="Código do colaborador"
          subtitulo={checklistSel?.nome}
          valor={codigo}
          mascarar={false}
          onTecla={premirTeclaAuth}
          onApagar={apagarAuth}
          acaoLabel="Continuar"
          acaoAtiva={codigo.length > 0}
          onAcao={avancarParaPin}
          onVoltar={() => {
            setCodigo("");
            setChecklistSel(null);
            setFase("lista");
          }}
        />
      )}

      {/* ===== PIN ===== */}
      {fase === "pin" && (
        <KeypadAuth
          titulo="PIN"
          subtitulo={checklistSel?.nome}
          valor={pin}
          mascarar
          onTecla={premirTeclaAuth}
          onApagar={apagarAuth}
          acaoLabel="Avançar"
          acaoAtiva={pin.length > 0}
          onAcao={avancarParaCamera}
          onVoltar={() => {
            setPin("");
            setFase("codigo");
          }}
        />
      )}

      {/* ===== CÂMARA ===== */}
      {fase === "camera" && (
        <View style={s.cameraWrap}>
          <Text style={s.cameraTitulo}>
            {checklistSel?.nome ?? "Checklist"}
            {"\n"}Foto de confirmação
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

          <Pressable style={s.shutter} onPress={capturarFoto}>
            <Text style={s.shutterTxt}>Confirmar e preencher</Text>
          </Pressable>
          <Pressable style={s.link} onPress={() => setFase("pin")}>
            <Text style={[s.linkTxt, { color: CINZA }]}>Cancelar</Text>
          </Pressable>
        </View>
      )}

      {/* ===== FORMULÁRIO ===== */}
      {fase === "formulario" && checklistSel && (
        <View style={s.root}>
          <View style={s.formularioCabecalho}>
            <Text style={s.formularioTitulo} numberOfLines={1}>
              {checklistSel.nome}
            </Text>
            <Text style={s.formularioSubtitulo}>
              {checklistSel.itens.length} itens
            </Text>
          </View>

          <ScrollView
            style={s.lista}
            contentContainerStyle={[s.listaConteudo, { paddingBottom: itemNumericoAtivo ? 280 : 100 }]}
            keyboardShouldPersistTaps="handled"
          >
            {checklistSel.itens.map((item) => (
              <ItemFormulario
                key={item.id}
                item={item}
                valor={respostas[item.id] ?? ""}
                acao={acoes[item.id] ?? ""}
                ativo={itemNumericoAtivo === item.id}
                onSetValor={(v) => {
                  setRespostas((prev) => ({ ...prev, [item.id]: v }));
                }}
                onSetAcao={(a) => {
                  setAcoes((prev) => ({ ...prev, [item.id]: a }));
                }}
                onActivarNumerico={() =>
                  setItemNumericoAtivo((prev) =>
                    prev === item.id ? null : item.id,
                  )
                }
                texteLimites={texteLimites(item)}
                avaliar={avaliarItem}
              />
            ))}
          </ScrollView>

          {/* Painel do teclado numérico (fixo em baixo quando activo) */}
          {itemNumericoAtivo && (
            <KeypadNumerico
              valor={respostas[itemNumericoAtivo] ?? ""}
              onTecla={(t) => premirTeclaNumerico(itemNumericoAtivo, t)}
              onApagar={() => apagarNumerico(itemNumericoAtivo)}
              onFechar={() => setItemNumericoAtivo(null)}
            />
          )}

          {/* Botão de submeter */}
          {!itemNumericoAtivo && (
            <View style={s.submitWrap}>
              <Pressable
                style={[s.submitBtn, !podeSubmeter() && s.submitBtnOff]}
                onPress={podeSubmeter() ? submeterChecklist : undefined}
              >
                <Text style={s.submitTxt}>Submeter checklist</Text>
              </Pressable>
              <Pressable style={s.link} onPress={reset}>
                <Text style={s.linkTxt}>Cancelar</Text>
              </Pressable>
            </View>
          )}
        </View>
      )}

      {/* ===== PROCESSAR ===== */}
      {fase === "processar" && (
        <View style={s.centro}>
          <ActivityIndicator size="large" color={TEAL} />
          <Text style={s.sub}>A submeter…</Text>
        </View>
      )}

      {/* ===== SUCESSO ===== */}
      {fase === "sucesso" && resumoSucesso && (
        <View style={[s.centro, { backgroundColor: TINTA }]}>
          <Text style={s.bigCheck}>✓</Text>
          <Text style={s.sucessoTxt}>Checklist submetida</Text>
          <Text style={s.sucessoMeta}>
            {resumoSucesso.respostas}{" "}
            {resumoSucesso.respostas === 1 ? "resposta" : "respostas"}
            {resumoSucesso.naoConformes > 0
              ? ` · ${resumoSucesso.naoConformes} não ${resumoSucesso.naoConformes === 1 ? "conforme" : "conformes"} corrigida${resumoSucesso.naoConformes === 1 ? "" : "s"}`
              : " · tudo conforme"}
          </Text>
          {/* Aviso de upload de foto falhado — registo persistiu, mas foto em falta */}
          {avisoFoto ? (
            <View style={s.avisoFotoWrap}>
              <Text style={s.avisoFotoTxt}>{avisoFoto}</Text>
            </View>
          ) : null}
        </View>
      )}

      {/* ===== ERRO ===== */}
      {fase === "erro" && (
        <View style={s.centro}>
          <ScrollView style={{ maxHeight: 300, width: "100%" }}>
            <Text style={s.erroTxt}>{textoErro}</Text>
          </ScrollView>
          <Pressable style={[s.tipoBtn, { marginTop: 24 }]} onPress={reset}>
            <Text style={s.tipoTxt}>Recomeçar</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Sub-componente: Keypad de autenticação (código / PIN)
// ---------------------------------------------------------------------------
function KeypadAuth(props: {
  titulo: string;
  subtitulo?: string;
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
      {props.subtitulo ? (
        <Text style={s.checklistNomeHeader}>{props.subtitulo}</Text>
      ) : null}
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

// ---------------------------------------------------------------------------
// Sub-componente: painel de teclado numérico (bottom, para itens numéricos)
// ---------------------------------------------------------------------------
function KeypadNumerico(props: {
  valor: string;
  onTecla: (t: string) => void;
  onApagar: () => void;
  onFechar: () => void;
}) {
  return (
    <View style={s.keypadNumPanel}>
      <View style={s.keypadNumVisorRow}>
        <Text style={s.keypadNumVisor}>{props.valor || "0"}</Text>
        <Pressable style={s.keypadNumFechar} onPress={props.onFechar}>
          <Text style={s.keypadNumFecharTxt}>Fechar ✓</Text>
        </Pressable>
      </View>
      <View style={s.grid}>
        {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((d) => (
          <Pressable
            key={d}
            style={s.tecla}
            onPress={() => props.onTecla(d)}
          >
            <Text style={s.teclaTxt}>{d}</Text>
          </Pressable>
        ))}
        <Pressable style={s.tecla} onPress={props.onApagar}>
          <Text style={s.teclaTxt}>⌫</Text>
        </Pressable>
        <Pressable style={s.tecla} onPress={() => props.onTecla("0")}>
          <Text style={s.teclaTxt}>0</Text>
        </Pressable>
        {/* Vírgula decimal — normalizada para ponto antes de enviar */}
        <Pressable style={s.tecla} onPress={() => props.onTecla(",")}>
          <Text style={s.teclaTxt}>,</Text>
        </Pressable>
      </View>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Sub-componente: item do formulário
// ---------------------------------------------------------------------------
function ItemFormulario({
  item,
  valor,
  acao,
  ativo,
  onSetValor,
  onSetAcao,
  onActivarNumerico,
  texteLimites,
  avaliar,
}: {
  item: ItemChecklist;
  valor: string;
  acao: string;
  ativo: boolean;
  onSetValor: (v: string) => void;
  onSetAcao: (a: string) => void;
  onActivarNumerico: () => void;
  texteLimites: string;
  avaliar: (item: ItemChecklist) => { conforme: boolean; motivo: string | null };
}) {
  const temResposta = valor.trim() !== "";

  // Para tipos que têm avaliação
  const { conforme, motivo } = temResposta || item.tipo_resposta === "booleano"
    ? avaliar(item)
    : { conforme: true, motivo: null };

  const naoConforme = temResposta && !conforme;

  if (item.tipo_resposta === "foto") {
    // Tipo foto não suportado — mostrar aviso claro, não bloquear outros
    return (
      <View style={[s.itemCard, s.itemCardFoto]}>
        <Text style={s.itemTexto}>{item.texto}</Text>
        {item.obrigatorio && (
          <Text style={s.itemObrigatorio}>obrigatório</Text>
        )}
        <Text style={s.itemFotoAviso}>
          ⚠ Itens com foto não são suportados nesta versão.
        </Text>
      </View>
    );
  }

  return (
    <View
      style={[
        s.itemCard,
        naoConforme && s.itemCardNaoConforme,
        ativo && s.itemCardAtivo,
      ]}
    >
      {/* Cabeçalho do item */}
      <View style={s.itemCabecalho}>
        <Text style={s.itemTexto}>{item.texto}</Text>
        {item.obrigatorio && (
          <Text style={s.itemObrigatorio}>obrigatório</Text>
        )}
      </View>

      {/* Limites (numérico) */}
      {item.tipo_resposta === "numerico" && texteLimites !== "" && (
        <Text style={s.itemLimites}>
          {item.unidade ? `${item.unidade} · ` : ""}Intervalo: {texteLimites}
        </Text>
      )}

      {/* Input por tipo */}
      {item.tipo_resposta === "numerico" && (
        <Pressable
          style={[s.numVisorBtn, ativo && { borderColor: TEAL, borderWidth: 2 }]}
          onPress={onActivarNumerico}
        >
          <Text style={[s.numVisorTxt, !valor && { color: CINZA }]}>
            {valor || "Tocar para inserir valor"}
            {valor && item.unidade ? ` ${item.unidade}` : ""}
          </Text>
        </Pressable>
      )}

      {item.tipo_resposta === "booleano" && (
        <View style={s.boolBtns}>
          <Pressable
            style={[
              s.boolBtn,
              valor === "true" && s.boolBtnSel,
            ]}
            onPress={() => onSetValor("true")}
          >
            <Text
              style={[s.boolTxt, valor === "true" && s.boolTxtSel]}
            >
              Sim
            </Text>
          </Pressable>
          <Pressable
            style={[
              s.boolBtn,
              valor === "false" && s.boolBtnSel,
            ]}
            onPress={() => onSetValor("false")}
          >
            <Text
              style={[s.boolTxt, valor === "false" && s.boolTxtSel]}
            >
              Não
            </Text>
          </Pressable>
        </View>
      )}

      {item.tipo_resposta === "texto" && (
        <TextInput
          style={s.textoInput}
          multiline
          numberOfLines={3}
          placeholder="Escreva a resposta…"
          placeholderTextColor={CINZA}
          value={valor}
          onChangeText={onSetValor}
        />
      )}

      {/* Badge de não conformidade */}
      {naoConforme && motivo && (
        <View style={s.naoConformeBadge}>
          <Text style={s.naoConformeTxt}>Não conforme: {motivo}</Text>
        </View>
      )}

      {/* Campo de ação corretiva (inline, obrigatório quando não conforme) */}
      {naoConforme && (
        <View style={s.acaoWrap}>
          <Text style={s.acaoLabel}>
            Ação corretiva{" "}
            <Text style={{ color: VERMELHO }}>*</Text>
          </Text>
          <TextInput
            style={[s.textoInput, acao.trim() === "" && { borderColor: VERMELHO }]}
            multiline
            numberOfLines={2}
            placeholder="Descreva a ação tomada…"
            placeholderTextColor={CINZA}
            value={acao}
            onChangeText={onSetAcao}
          />
        </View>
      )}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Estilos
// ---------------------------------------------------------------------------
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

  tituloPainel: {
    fontSize: 22,
    color: TINTA,
    fontWeight: "700",
    textAlign: "center",
    paddingTop: 80,
    paddingBottom: 12,
  },

  // --- Offline --------------------------------------------------------------
  offlineWrap: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 32,
  },
  offlineTxt: {
    fontSize: 20,
    color: TINTA,
    fontWeight: "700",
    textAlign: "center",
    marginBottom: 8,
  },
  offlineSub: {
    fontSize: 15,
    color: CINZA,
    textAlign: "center",
    marginBottom: 24,
  },
  btnTentar: {
    backgroundColor: TEAL,
    paddingVertical: 14,
    paddingHorizontal: 32,
    borderRadius: 12,
  },
  btnTentarTxt: { color: PAPEL, fontWeight: "700", fontSize: 16 },

  // --- Lista ----------------------------------------------------------------
  lista: { flex: 1 },
  listaConteudo: { padding: 16, gap: 12 },

  checklistCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    padding: 20,
    borderWidth: 1,
    borderColor: "#E3E1DA",
  },
  checklistNome: {
    fontSize: 18,
    color: TINTA,
    fontWeight: "700",
    marginBottom: 4,
  },
  checklistMeta: { fontSize: 13, color: CINZA, marginBottom: 10 },
  checklistIniciar: { fontSize: 15, color: TEAL, fontWeight: "700" },

  semChecklists: {
    fontSize: 16,
    color: CINZA,
    textAlign: "center",
    marginTop: 40,
  },

  // --- Autenticação (Keypad) ------------------------------------------------
  centro: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  checklistNomeHeader: {
    fontSize: 15,
    color: TEAL,
    fontWeight: "600",
    marginBottom: 12,
    textAlign: "center",
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
  link: { marginTop: 22 },
  linkTxt: { fontSize: 15, color: CINZA, textDecorationLine: "underline" },

  // --- Câmara ---------------------------------------------------------------
  cameraWrap: {
    flex: 1,
    backgroundColor: TINTA,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  cameraTitulo: {
    color: PAPEL,
    fontSize: 20,
    fontWeight: "700",
    marginBottom: 24,
    textAlign: "center",
    lineHeight: 28,
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

  // --- Formulário -----------------------------------------------------------
  formularioCabecalho: {
    paddingTop: 72,
    paddingHorizontal: 20,
    paddingBottom: 8,
    borderBottomWidth: 1,
    borderBottomColor: "#E3E1DA",
    backgroundColor: PAPEL,
  },
  formularioTitulo: {
    fontSize: 18,
    color: TINTA,
    fontWeight: "700",
  },
  formularioSubtitulo: { fontSize: 13, color: CINZA },

  itemCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: "#E3E1DA",
  },
  itemCardAtivo: { borderColor: TEAL, borderWidth: 2 },
  itemCardNaoConforme: { borderColor: VERMELHO, borderWidth: 2 },
  itemCardFoto: { borderColor: "#E9A23B", borderWidth: 1 },

  itemCabecalho: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-start",
    marginBottom: 8,
  },
  itemTexto: {
    fontSize: 16,
    color: TINTA,
    fontWeight: "600",
    flex: 1,
    marginRight: 8,
  },
  itemObrigatorio: {
    fontSize: 11,
    color: VERMELHO,
    fontWeight: "700",
    textTransform: "uppercase",
    marginTop: 2,
  },
  itemLimites: {
    fontSize: 13,
    color: CINZA,
    marginBottom: 10,
  },
  itemFotoAviso: {
    fontSize: 14,
    color: "#9A6A1E",
    marginTop: 8,
    fontStyle: "italic",
  },

  numVisorBtn: {
    backgroundColor: PAPEL,
    borderWidth: 1,
    borderColor: "#E3E1DA",
    borderRadius: 10,
    paddingVertical: 14,
    paddingHorizontal: 16,
    marginTop: 4,
  },
  numVisorTxt: { fontSize: 24, color: TINTA, fontWeight: "600" },

  boolBtns: {
    flexDirection: "row",
    gap: 12,
    marginTop: 4,
  },
  boolBtn: {
    flex: 1,
    paddingVertical: 16,
    borderRadius: 12,
    backgroundColor: "#FFFFFF",
    borderWidth: 1,
    borderColor: "#E3E1DA",
    alignItems: "center",
  },
  boolBtnSel: { backgroundColor: TINTA, borderColor: TINTA },
  boolTxt: { fontSize: 18, color: TINTA, fontWeight: "600" },
  boolTxtSel: { color: PAPEL },

  textoInput: {
    backgroundColor: PAPEL,
    borderWidth: 1,
    borderColor: "#E3E1DA",
    borderRadius: 10,
    padding: 12,
    fontSize: 16,
    color: TINTA,
    marginTop: 4,
    textAlignVertical: "top",
  },

  naoConformeBadge: {
    backgroundColor: "#B23A3A18",
    borderRadius: 8,
    padding: 8,
    marginTop: 10,
  },
  naoConformeTxt: {
    fontSize: 13,
    color: VERMELHO,
    fontWeight: "600",
  },

  acaoWrap: { marginTop: 12 },
  acaoLabel: { fontSize: 14, color: TINTA, fontWeight: "600", marginBottom: 4 },

  // --- Keypad numérico (bottom panel) ---------------------------------------
  keypadNumPanel: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: "#FFFFFF",
    borderTopWidth: 1,
    borderTopColor: "#E3E1DA",
    padding: 12,
    paddingBottom: 24,
  },
  keypadNumVisorRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 8,
  },
  keypadNumVisor: {
    fontSize: 28,
    color: TINTA,
    fontWeight: "700",
    letterSpacing: 2,
  },
  keypadNumFechar: {
    backgroundColor: TEAL,
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 10,
  },
  keypadNumFecharTxt: { color: PAPEL, fontWeight: "700", fontSize: 15 },

  // --- Submit ---------------------------------------------------------------
  submitWrap: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: PAPEL,
    borderTopWidth: 1,
    borderTopColor: "#E3E1DA",
    padding: 16,
    paddingBottom: 32,
    alignItems: "center",
  },
  submitBtn: {
    backgroundColor: TEAL,
    paddingVertical: 18,
    paddingHorizontal: 48,
    borderRadius: 14,
    width: "100%",
    alignItems: "center",
  },
  submitBtnOff: { opacity: 0.4 },
  submitTxt: { color: PAPEL, fontSize: 18, fontWeight: "700" },

  // --- Sucesso/Erro ---------------------------------------------------------
  bigCheck: {
    fontSize: 96,
    color: PAPEL,
    fontWeight: "900",
    marginBottom: 16,
  },
  sucessoTxt: {
    fontSize: 24,
    color: PAPEL,
    fontWeight: "700",
    marginBottom: 8,
    textAlign: "center",
  },
  sucessoMeta: {
    fontSize: 16,
    color: PAPEL,
    opacity: 0.85,
    textAlign: "center",
  },
  // Aviso amarelo no ecrã de sucesso quando o upload da foto falhou.
  // O registo já persistiu — o aviso é informativo, não bloqueante.
  avisoFotoWrap: {
    backgroundColor: "#E9A23B22",
    borderColor: "#E9A23B",
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 16,
    paddingVertical: 12,
    marginTop: 20,
    maxWidth: 360,
  },
  avisoFotoTxt: {
    fontSize: 13,
    color: "#E9A23B",
    fontWeight: "600",
    textAlign: "center",
    lineHeight: 20,
  },
  erroTxt: {
    fontSize: 16,
    color: VERMELHO,
    fontWeight: "600",
    textAlign: "center",
    lineHeight: 24,
  },
  sub: { fontSize: 16, color: CINZA, marginTop: 6 },
  tipoBtn: {
    paddingVertical: 18,
    borderRadius: 14,
    backgroundColor: "#FFFFFF",
    borderWidth: 1,
    borderColor: "#E3E1DA",
    alignItems: "center",
    paddingHorizontal: 32,
  },
  tipoTxt: { fontSize: 20, color: TINTA, fontWeight: "600" },
});
