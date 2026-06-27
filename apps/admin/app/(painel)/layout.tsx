"use client";
import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import Image from "next/image";

const NAV = [
  { href: "/", label: "Início" },
  { href: "/colaboradores", label: "Colaboradores" },
];

export default function PainelLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [verificado, setVerificado] = useState(false);
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) {
        router.replace("/login");
        return;
      }
      setEmail(data.session.user.email ?? null);
      setVerificado(true);
    });
  }, [router]);

  async function sair() {
    await supabase.auth.signOut();
    router.replace("/login");
  }

  if (!verificado)
    return (
      <div className="min-h-screen grid place-items-center text-cinza">
        A carregar…
      </div>
    );

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 bg-tinta text-papel flex flex-col">
        <div className="px-6 py-6">
          <Link href="/" className="block">
            <Image
              src="/wordmark-papel.png"
              alt="CoreVero"
              width={150}
              height={59}
              priority
            />
          </Link>
        </div>
        <nav className="flex-1 px-3 space-y-1">
          {NAV.map((n) => {
            const ativo =
              n.href === "/" ? pathname === "/" : pathname.startsWith(n.href);
            return (
              <Link
                key={n.href}
                href={n.href}
                className={`block rounded-lg px-3 py-2 text-sm font-medium transition ${ativo ? "bg-white/10" : "text-papel/70 hover:bg-white/5 hover:text-papel"}`}
              >
                {n.label}
              </Link>
            );
          })}
        </nav>
        <div className="px-6 py-4 border-t border-white/10 text-xs text-papel/60">
          <p className="truncate mb-2">{email}</p>
          <button
            onClick={sair}
            className="text-papel/80 hover:text-papel underline"
          >
            Terminar sessão
          </button>
        </div>
      </aside>
      <main className="flex-1 p-8 max-w-5xl">{children}</main>
    </div>
  );
}
