// PicagemScreen.tsx
// Kiosk — fluxo: código -> PIN -> tipo -> foto -> picagem enfileirada.
//
// Sprint 3a (Opção 1): a captura escreve numa FILA local (outbox) e mostra ✓
// assim que o item está duravelmente guardado — não espera pelo servidor. A
// fila drena (registar + upload) quando há rede. Um blip a meio da transação
// deixa de perder a picagem.
//
// O bilhete (autorizacao_id) é emitido ONLINE pela iniciar_picagem antes de a
// câmara abrir; só o registo+upload é que vai para a fila. Sem PIN na fila.
//
// Dependências: expo-camera, expo-crypto, base64-arraybuffer, expo-sqlite
//   npx expo install expo-camera expo-sqlite
//   npm i base64-arraybuffer

import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator, AppState, Dimensions, Image, Pressable, StyleSheet, Text, View,
} from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Crypto from 'expo-crypto';
import { supabase } from './lib/supabase';
import { enfileirar, drenar, contarPendentes } from './lib/outbox';

// --- Marca CoreVero -----------------------------------------------------------
const TINTA = '#10202E';
const TEAL  = '#16A37D';
const PAPEL = '#F7F6F2';
const CINZA = '#6B7C8C';

// Diâmetro da janela circular da câmara (limitado para não colar às margens).
const CIRCULO = Math.min(Dimensions.get('window').width - 64, 320);

// --- Tipos de picagem ---------------------------------------------------------
type Tipo = 'entrada' | 'saida' | 'inicio_intervalo' | 'fim_intervalo';

const LABEL: Record<Tipo, string> = {
  entrada:          'Entrada',
  saida:            'Saída',
  inicio_intervalo: 'Início de pausa',
  fim_intervalo:    'Fim de pausa',
};

// Sugestão do próximo tipo a partir da última picagem de hoje.
// É uma DICA (a validação dura fica para mais tarde); o colaborador pode escolher
// qualquer opção apresentada.
function opcoesPara(ultima: Tipo | null): { sugerida: Tipo; opcoes: Tipo[] } {
  switch (ultima) {
    case 'entrada':
    case 'fim_intervalo':
      // em turno -> pode ir para pausa ou sair
      return { sugerida: 'saida', opcoes: ['inicio_intervalo', 'saida'] };
    case 'inicio_intervalo':
      // em pausa -> só volta da pausa
      return { sugerida: 'fim_intervalo', opcoes: ['fim_intervalo'] };
    case 'saida':
    case null:
    default:
      // fora de turno -> entra
      return { sugerida: 'entrada', opcoes: ['entrada'] };
  }
}

function horaLisboa(iso?: string | null): string {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('pt-PT', {
    hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Lisbon',
  });
}

type Fase = 'codigo' | 'pin' | 'tipo' | 'camera' | 'processar' | 'sucesso' | 'erro';

export default function PicagemScreen({ lojaNome }: { lojaNome?: string }) {
  const [fase, setFase] = useState<Fase>('codigo');
  const [codigo, setCodigo] = useState('');
  const [pin, setPin] = useState('');
  const [nome, setNome] = useState('');
  const [autorizacaoId, setAutorizacaoId] = useState<string | null>(null);
  const [ultimaTipo, setUltimaTipo] = useState<Tipo | null>(null);
  const [ultimaMomento, setUltimaMomento] = useState<string | null>(null);
  const [tipo, setTipo] = useState<Tipo | null>(null);
  const [erro, setErro] = useState('');
  const [sucessoTxt, setSucessoTxt] = useState('');
  const [pendentes, setPendentes] = useState(0);

  const [perm, requestPerm] = useCameraPermissions();
  const cameraRef = useRef<CameraView>(null);
  const emCurso = useRef(false); // trava de duplo-toque

  // drenar a fila: ao montar, ao voltar a primeiro plano, e a cada 15s.
  // O próprio drain é o teste de rede — se não há, o item fica e tenta depois.
  async function sincronizar() {
    await drenar();
    setPendentes(await contarPendentes());
  }
  useEffect(() => {
    sincronizar();
    const sub = AppState.addEventListener('change', (st) => {
      if (st === 'active') sincronizar();
    });
    const iv = setInterval(sincronizar, 15000);
    return () => { sub.remove(); clearInterval(iv); };
  }, []);

  // auto-reset após sucesso/erro
  useEffect(() => {
    if (fase === 'sucesso' || fase === 'erro') {
      const t = setTimeout(reset, fase === 'sucesso' ? 3500 : 4000);
      return () => clearTimeout(t);
    }
  }, [fase]);

  function reset() {
    setCodigo(''); setPin(''); setNome('');
    setAutorizacaoId(null);
    setUltimaTipo(null); setUltimaMomento(null);
    setTipo(null); setErro(''); setSucessoTxt('');
    emCurso.current = false;
    setFase('codigo');
  }

  function falhar(msg: string) {
    setErro(msg);
    emCurso.current = false;
    setFase('erro');
  }

  // teclado numérico partilhado pelas fases código/PIN
  function premirTecla(d: string) {
    if (fase === 'codigo') setCodigo((s) => (s.length < 8 ? s + d : s));
    else if (fase === 'pin') setPin((s) => (s.length < 8 ? s + d : s));
  }
  function apagar() {
    if (fase === 'codigo') setCodigo((s) => s.slice(0, -1));
    else if (fase === 'pin') setPin((s) => s.slice(0, -1));
  }

  // PASSO 1 -> 2: código introduzido
  function avancarParaPin() {
    if (codigo.trim().length === 0) return;
    setFase('pin');
  }

  // PASSO 2: validar PIN no servidor (a câmara NÃO abre se isto falhar)
  async function validarPin() {
    if (emCurso.current) return;
    if (pin.trim().length === 0) return;
    emCurso.current = true;
    setFase('processar');
    const { data, error } = await supabase.rpc('iniciar_picagem', {
      p_codigo_pessoal: codigo.trim(),
      p_pin: pin.trim(),
    });
    emCurso.current = false;
    if (error || !data) {
      const msg = error?.message ?? '';
      if (/revogad/i.test(msg)) {
        return falhar('Este dispositivo foi revogado. Contacte o gestor.');
      }
      return falhar('Código ou PIN inválido.');
    }
    setNome(data.nome ?? '');
    setAutorizacaoId(data.autorizacao_id ?? null);
    setUltimaTipo((data.ultima_tipo as Tipo) ?? null);
    setUltimaMomento(data.ultima_momento ?? null);
    setTipo(opcoesPara((data.ultima_tipo as Tipo) ?? null).sugerida);
    setFase('tipo');
  }

  // PASSO 3 -> 4: tipo escolhido, abrir câmara (pedir permissão se preciso)
  async function escolherTipo(t: Tipo) {
    setTipo(t);
    if (!perm?.granted) {
      const r = await requestPerm();
      if (!r.granted) return falhar('Sem permissão de câmara.');
    }
    setFase('camera');
  }

  // PASSO 4: capturar foto -> enfileirar (a fila trata de registar + upload)
  async function capturarERegistar() {
    if (emCurso.current || !cameraRef.current || !tipo || !autorizacaoId) return;
    emCurso.current = true;
    setFase('processar');

    // hora autoritária = momento do toque
    const momento = new Date().toISOString();
    // chave de idempotência: id do item da fila, reutilizada em todos os retries
    const chave = Crypto.randomUUID();

    let base64: string | undefined;
    try {
      const foto = await cameraRef.current.takePictureAsync({ quality: 0.5, base64: true });
      base64 = foto?.base64;
    } catch {
      return falhar('Falha ao capturar a foto.');
    }
    if (!base64) return falhar('Falha ao capturar a foto.');

    // Escreve na fila local. A partir daqui a picagem está DURÁVEL — sobrevive a
    // fechar a app e a falta de rede. O ✓ é honesto: o registo legal está salvo.
    try {
      await enfileirar({
        id: chave,
        autorizacao_id: autorizacaoId,
        tipo,
        momento,
        foto_b64: base64,
      });
    } catch {
      return falhar('Falha ao guardar a picagem no dispositivo.');
    }

    emCurso.current = false;
    setSucessoTxt(`${LABEL[tipo]} registada às ${horaLisboa(momento)}`);
    setFase('sucesso');

    // drena em segundo plano — não bloqueia o ✓
    sincronizar();
  }

  // --- RENDER -----------------------------------------------------------------
  return (
    <View style={s.root}>
      {lojaNome && fase !== 'camera' && fase !== 'sucesso' ? (
        <Text style={s.lojaLabel}>{lojaNome}</Text>
      ) : null}

      {pendentes > 0 && fase !== 'camera' && fase !== 'sucesso' ? (
        <View style={s.pendentes}>
          <Text style={s.pendentesTxt}>
            {pendentes} {pendentes === 1 ? 'picagem por enviar' : 'picagens por enviar'}
          </Text>
        </View>
      ) : null}

      {fase === 'codigo' && (
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

      {fase === 'pin' && (
        <Keypad
          titulo="PIN"
          valor={pin}
          mascarar
          onTecla={premirTecla}
          onApagar={apagar}
          acaoLabel="Validar"
          acaoAtiva={pin.length > 0}
          onAcao={validarPin}
          onVoltar={() => { setPin(''); setFase('codigo'); }}
        />
      )}

      {fase === 'tipo' && tipo && (
        <View style={s.centro}>
          <Text style={s.ola}>Olá, {nome}</Text>
          {ultimaTipo ? (
            <Text style={s.sub}>
              Última: {LABEL[ultimaTipo]} às {horaLisboa(ultimaMomento)}
            </Text>
          ) : (
            <Text style={s.sub}>Sem picagens hoje</Text>
          )}
          <View style={s.tipos}>
            {opcoesPara(ultimaTipo).opcoes.map((t) => (
              <Pressable
                key={t}
                style={[s.tipoBtn, tipo === t && s.tipoBtnSel]}
                onPress={() => escolherTipo(t)}
              >
                <Text style={[s.tipoTxt, tipo === t && s.tipoTxtSel]}>{LABEL[t]}</Text>
              </Pressable>
            ))}
          </View>
          <Pressable style={s.link} onPress={reset}>
            <Text style={s.linkTxt}>Cancelar</Text>
          </Pressable>
        </View>
      )}

      {fase === 'camera' && (
        <View style={s.cameraWrap}>
          <Text style={s.cameraTitulo}>
            {nome}{tipo ? ` · ${LABEL[tipo]}` : ''}
          </Text>

          <View style={s.circulo}>
            <CameraView ref={cameraRef} style={StyleSheet.absoluteFill} facing="front" />
          </View>

          <Image
            source={require('./assets/wordmark-papel.png')}
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

      {fase === 'processar' && (
        <View style={s.centro}>
          <ActivityIndicator size="large" color={TEAL} />
          <Text style={s.sub}>A processar…</Text>
        </View>
      )}

      {fase === 'sucesso' && (
        <View style={[s.centro, { backgroundColor: TEAL }]}>
          <Text style={s.bigCheck}>✓</Text>
          <Text style={s.sucesso}>{sucessoTxt}</Text>
        </View>
      )}

      {fase === 'erro' && (
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
  const mostrado = props.mascarar ? '•'.repeat(props.valor.length) : props.valor;
  return (
    <View style={s.centro}>
      <Text style={s.titulo}>{props.titulo}</Text>
      <Text style={s.visor}>{mostrado || ' '}</Text>
      <View style={s.grid}>
        {['1','2','3','4','5','6','7','8','9'].map((d) => (
          <Pressable key={d} style={s.tecla} onPress={() => props.onTecla(d)}>
            <Text style={s.teclaTxt}>{d}</Text>
          </Pressable>
        ))}
        <Pressable style={s.tecla} onPress={props.onApagar}>
          <Text style={s.teclaTxt}>⌫</Text>
        </Pressable>
        <Pressable style={s.tecla} onPress={() => props.onTecla('0')}>
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
  root:   { flex: 1, backgroundColor: PAPEL },
  lojaLabel: { position: 'absolute', top: 52, alignSelf: 'center', fontSize: 13, color: CINZA, fontWeight: '600', zIndex: 10 },
  pendentes: { position: 'absolute', top: 78, alignSelf: 'center', backgroundColor: '#E9A23B22', borderColor: '#E9A23B', borderWidth: 1, borderRadius: 999, paddingHorizontal: 12, paddingVertical: 4, zIndex: 10 },
  pendentesTxt: { fontSize: 12, color: '#9A6A1E', fontWeight: '700' },
  centro: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 },

  titulo: { fontSize: 22, color: TINTA, marginBottom: 12, fontWeight: '600' },
  visor:  { fontSize: 44, color: TINTA, letterSpacing: 6, minHeight: 60, fontWeight: '700' },

  grid: { width: 300, flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', marginTop: 16 },
  tecla: {
    width: 92, height: 72, marginVertical: 6, borderRadius: 14,
    alignItems: 'center', justifyContent: 'center', backgroundColor: '#FFFFFF',
    borderWidth: 1, borderColor: '#E3E1DA',
  },
  teclaOk:  { backgroundColor: TEAL, borderColor: TEAL },
  teclaOff: { opacity: 0.4 },
  teclaTxt: { fontSize: 26, color: TINTA, fontWeight: '600' },

  acao:    { marginTop: 18, backgroundColor: TINTA, paddingVertical: 16, paddingHorizontal: 48, borderRadius: 14 },
  acaoTxt: { color: PAPEL, fontSize: 18, fontWeight: '700' },

  ola: { fontSize: 28, color: TINTA, fontWeight: '700' },
  sub: { fontSize: 16, color: CINZA, marginTop: 6 },

  tipos:    { marginTop: 28, width: '100%', maxWidth: 420, gap: 12 },
  tipoBtn:  { paddingVertical: 18, borderRadius: 14, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E3E1DA', alignItems: 'center' },
  tipoBtnSel: { backgroundColor: TINTA, borderColor: TINTA },
  tipoTxt:  { fontSize: 20, color: TINTA, fontWeight: '600' },
  tipoTxtSel: { color: PAPEL },

  cameraWrap:    { flex: 1, backgroundColor: TINTA, alignItems: 'center', justifyContent: 'center', padding: 24 },
  cameraTitulo:  { color: PAPEL, fontSize: 22, fontWeight: '700', marginBottom: 28, textAlign: 'center' },
  circulo: {
    width: CIRCULO, height: CIRCULO, borderRadius: CIRCULO / 2,
    overflow: 'hidden', backgroundColor: '#000',
    borderWidth: 3, borderColor: TEAL,
  },
  wordmark: { width: 180, height: 44, marginTop: 28, marginBottom: 8, opacity: 0.95 },
  shutter:    { backgroundColor: TEAL, paddingVertical: 18, paddingHorizontal: 40, borderRadius: 16, marginTop: 16 },
  shutterTxt: { color: PAPEL, fontSize: 20, fontWeight: '700' },

  bigCheck: { fontSize: 96, color: PAPEL, fontWeight: '900' },
  sucesso:  { fontSize: 22, color: PAPEL, fontWeight: '700', marginTop: 8, textAlign: 'center' },

  erro: { fontSize: 20, color: '#B23A3A', fontWeight: '600', marginBottom: 20, textAlign: 'center' },

  link:    { marginTop: 22 },
  linkTxt: { fontSize: 15, color: CINZA, textDecorationLine: 'underline' },
});
