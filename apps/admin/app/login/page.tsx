"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [aEntrar, setAEntrar] = useState(false);

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setAEntrar(true);
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    setAEntrar(false);
    if (error) return setErro(error.message);
    router.push("/");
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-6">
      <form onSubmit={entrar} className="w-full max-w-sm space-y-4">
        <h1 className="text-2xl font-semibold">CoreVero — entrar</h1>
        <input
          type="email"
          placeholder="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          className="w-full border rounded px-3 py-2"
        />
        <input
          type="password"
          placeholder="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          className="w-full border rounded px-3 py-2"
        />
        {erro && <p className="text-red-600 text-sm">{erro}</p>}
        <button
          type="submit"
          disabled={aEntrar}
          className="w-full bg-black text-white rounded py-2 disabled:opacity-50"
        >
          {aEntrar ? "A entrar…" : "Entrar"}
        </button>
      </form>
    </main>
  );
}
