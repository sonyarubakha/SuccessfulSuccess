"use client"

import { useRouter } from "next/navigation"
import { useEffect, useRef } from "react"

import { useAuth } from "@/components/auth-provider"
import { AuthLoading } from "@/components/require-auth"
import { isAuthConfigured } from "@/lib/auth"

export default function LoginPage() {
  const { status, signIn } = useAuth()
  const router = useRouter()
  const started = useRef(false)

  useEffect(() => {
    if (!isAuthConfigured) return

    if (status === "signedIn") {
      router.replace("/today/")
      return
    }

    if (status === "signedOut" && !started.current) {
      started.current = true
      void signIn()
    }
  }, [status, signIn, router])

  if (!isAuthConfigured) {
    return (
      <main className="flex min-h-screen items-center justify-center p-6">
        <p>Sign-in is not configured.</p>
      </main>
    )
  }

  return <AuthLoading label="Opening sign-in…" />
}
