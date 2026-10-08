"use client"

import { useRouter } from "next/navigation"
import { useEffect } from "react"

import { useAuth } from "@/components/auth-provider"
import { AuthLoading } from "@/components/require-auth"

export default function Home() {
  const { status } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (status === "signedIn") {
      router.replace("/today/")
    }

    if (status === "signedOut") {
      router.replace("/login/")
    }
  }, [status, router])

  return <AuthLoading />
}
