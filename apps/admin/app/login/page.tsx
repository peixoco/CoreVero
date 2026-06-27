"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
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
    <main className="min-h-screen grid place-items-center p-6">
      <form
        onSubmit={entrar}
        className="w-full max-w-sm bg-white rounded-2xl border border-black/5 shadow-sm p-8 space-y-5"
      >
        <Image
          src="/wordmark.png"
          alt="CoreVero"
          width={200}
          height={100}
          priority
          className="mx-auto"
        />
        <input
          type="email"
          placeholder="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          className="w-full rounded-lg border border-cinza/30 px-3 py-2 outline-none focus:border-teal focus:ring-2 focus:ring-teal/20"
        />
        <input
          type="password"
          placeholder="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          className="w-full rounded-lg border border-cinza/30 px-3 py-2 outline-none focus:border-teal focus:ring-2 focus:ring-teal/20"
        />
        {erro && <p className="text-red-600 text-sm">{erro}</p>}
        <button
          type="submit"
          disabled={aEntrar}
          className="w-full rounded-lg bg-teal text-papel py-2.5 font-medium hover:brightness-110 disabled:opacity-50"
        >
          {aEntrar ? "A entrar…" : "Entrar"}
        </button>
      </form>
    </main>
  );
}
