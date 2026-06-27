"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import Link from "next/link";

export default function Home() {
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);
  const [aVerificar, setAVerificar] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) return router.replace("/login");
      setEmail(data.session.user.email ?? null);
      setAVerificar(false);
    });
  }, [router]);

  async function sair() {
    await supabase.auth.signOut();
    router.replace("/login");
  }

  if (aVerificar) return <main className="p-6">A carregar…</main>;

  return (
    <main className="p-6 space-y-4">
      <h1 className="text-2xl font-semibold">CoreVero — Admin</h1>
      <p>
        Sessão: <strong>{email}</strong>
      </p>
      <button onClick={sair} className="border rounded px-3 py-1">
        Terminar sessão
      </button>
      <Link href="/colaboradores" className="underline">
        Gerir colaboradores →
      </Link>
    </main>
  );
}
