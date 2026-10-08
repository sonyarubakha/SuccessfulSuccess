"use client"

import { useQueryClient } from "@tanstack/react-query"

import { createContext, useCallback, useContext, useEffect, useMemo, useRef } from "react"
import { AuthProvider as OidcAuthProvider, useAuth as useOidcAuth } from "react-oidc-context"

import { syncMe } from "@/lib/api"
import { getUserManager, isAuthConfigured, signOutFromCognito } from "@/lib/auth"

type AuthStatus = "loading" | "signedIn" | "signedOut"

type AuthUser = {
  sub: string
  email?: string
  name?: string
}

type AuthContextValue = {
  status: AuthStatus
  user: AuthUser | null
  signIn: () => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue>({
  status: "loading",
  user: null,
  signIn: async () => {},
  signOut: async () => {},
})

function AuthBridge({ children }: { children: React.ReactNode }) {
  const oidc = useOidcAuth()
  const queryClient = useQueryClient()
  const syncedSubject = useRef<string | null>(null)

  useEffect(() => {
    const user = oidc.user
    const subject = user?.profile.sub

    if (!oidc.isAuthenticated || !user || !subject || !user.id_token) {
      return
    }

    if (syncedSubject.current === subject) {
      return
    }

    syncedSubject.current = subject

    void syncMe(user.id_token).catch((error) => {
      console.error("Failed to sync user profile", error)
    })
  }, [oidc.isAuthenticated, oidc.user])

  const signIn = useCallback(async () => {
    await oidc.signinRedirect()
  }, [oidc])

  const signOut = useCallback(async () => {
    queryClient.clear()
    await signOutFromCognito()
  }, [queryClient])

  const value = useMemo<AuthContextValue>(() => {
    const profile = oidc.user?.profile

    return {
      status: oidc.isLoading ? "loading" : oidc.isAuthenticated ? "signedIn" : "signedOut",

      user:
        oidc.isAuthenticated && profile?.sub
          ? {
              sub: profile.sub,
              email: typeof profile.email === "string" ? profile.email : undefined,
              name: typeof profile.name === "string" ? profile.name : undefined,
            }
          : null,

      signIn,
      signOut,
    }
  }, [oidc.isLoading, oidc.isAuthenticated, oidc.user, signIn, signOut])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const manager = useMemo(() => getUserManager(), [])

  if (!isAuthConfigured) {
    return (
      <AuthContext.Provider
        value={{
          status: "signedOut",
          user: null,
          signIn: async () => {},
          signOut: async () => {},
        }}
      >
        {children}
      </AuthContext.Provider>
    )
  }

  if (!manager) {
    return (
      <AuthContext.Provider
        value={{
          status: "loading",
          user: null,
          signIn: async () => {},
          signOut: async () => {},
        }}
      >
        {children}
      </AuthContext.Provider>
    )
  }

  return (
    <OidcAuthProvider
      userManager={manager}
      onSigninCallback={() => {
        window.history.replaceState({}, document.title, "/")
      }}
    >
      <AuthBridge>{children}</AuthBridge>
    </OidcAuthProvider>
  )
}

export function useAuth() {
  return useContext(AuthContext)
}
