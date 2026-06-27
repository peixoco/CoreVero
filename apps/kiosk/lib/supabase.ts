import 'react-native-url-polyfill/auto'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { createClient } from '@supabase/supabase-js'

// Chave publishable (pública, protegida pela RLS) — pode viver no cliente.
const url = 'https://xghfsudvpsgqkslobttj.supabase.co'
const key = 'sb_publishable_4W9n0MYy80jx-memioDqwQ_HygG80St'

export const supabase = createClient(url, key, {
  auth: {
    storage: AsyncStorage,
    persistSession: true,      // "nunca faz logout"
    autoRefreshToken: true,    // renova o token sozinho
    detectSessionInUrl: false, // não é web
  },
})
