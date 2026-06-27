"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import { supabase } from "@/lib/supabase";

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
      <Image
        src="/wordmark.png"
        alt="CoreVero"
        width={200}
        height={100}
        priority
      />
      <p>
        Sessão: <strong>{email}</strong>
      </p>
      <nav className="flex gap-4">
        <Link href="/colaboradores" className="underline">
          Gerir colaboradores →
        </Link>
      </nav>
      <button onClick={sair} className="border rounded px-3 py-1">
        Terminar sessão
      </button>
    </main>
  );
}
