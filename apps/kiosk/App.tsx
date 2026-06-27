import 'react-native-url-polyfill/auto'
import { useEffect, useState } from 'react'
import { View, Text, TextInput, Pressable, ActivityIndicator, StyleSheet } from 'react-native'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './lib/supabase'

export default function App() {
  const [pronto, setPronto] = useState(false)
  const [sessao, setSessao] = useState(false)
  const [lojaNome, setLojaNome] = useState<string | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [aEntrar, setAEntrar] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (data.session) { await carregarLoja(data.session); setSessao(true) }
      setPronto(true)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSessao(!!s)
      if (s) carregarLoja(s)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  async function carregarLoja(session: Session) {
    const lojaId = (session.user.app_metadata as { loja_id?: string })?.loja_id
    if (!lojaId) { setLojaNome('(sem loja no token)'); return }
    const { data } = await supabase.from('loja').select('nome').eq('id', lojaId).single()
    setLojaNome(data?.nome ?? '(loja não encontrada)')
  }

  async function entrar() {
    setErro(null); setAEntrar(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setAEntrar(false)
    if (error) setErro(error.message)
  }

  if (!pronto) return <View style={s.center}><ActivityIndicator color="#16A37D" /></View>

  if (!sessao) return (
    <View style={s.center}>
      <Text style={s.titulo}>CoreVero — configurar kiosk</Text>
      <TextInput style={s.input} placeholder="email da loja" autoCapitalize="none" keyboardType="email-address" value={email} onChangeText={setEmail} />
      <TextInput style={s.input} placeholder="password" secureTextEntry value={password} onChangeText={setPassword} />
      {erro ? <Text style={s.erro}>{erro}</Text> : null}
      <Pressable style={s.botao} onPress={entrar} disabled={aEntrar}>
        <Text style={s.botaoTexto}>{aEntrar ? 'A entrar…' : 'Entrar'}</Text>
      </Pressable>
    </View>
  )

  return (
    <View style={s.center}>
      <Text style={s.titulo}>Sessão de loja ativa</Text>
      <Text style={s.loja}>{lojaNome}</Text>
      <Text style={s.nota}>Dispositivo pronto para picagens.</Text>
    </View>
  )
}

const s = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 24, backgroundColor: '#F7F6F2' },
  titulo: { fontSize: 20, fontWeight: '700', color: '#10202E', marginBottom: 16 },
  loja: { fontSize: 28, fontWeight: '800', color: '#16A37D', marginBottom: 8 },
  nota: { color: '#6B7C8C' },
  input: { width: 280, backgroundColor: 'white', borderColor: '#6B7C8C55', borderWidth: 1, borderRadius: 10, padding: 12, marginBottom: 12 },
  botao: { backgroundColor: '#16A37D', borderRadius: 10, paddingVertical: 12, paddingHorizontal: 24, marginTop: 8 },
  botaoTexto: { color: '#F7F6F2', fontWeight: '700' },
  erro: { color: '#c0392b', marginBottom: 8 },
})
