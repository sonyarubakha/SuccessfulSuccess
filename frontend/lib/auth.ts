import { UserManager, WebStorageStateStore } from "oidc-client-ts"

export const authConfig = {
  userPoolId: process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID ?? "",
  clientId: process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? "",
  domain: process.env.NEXT_PUBLIC_COGNITO_DOMAIN ?? "",
}

export const isAuthConfigured = Boolean(
  authConfig.userPoolId && authConfig.clientId && authConfig.domain,
)

export const authority = authConfig.userPoolId
  ? `https://cognito-idp.us-east-1.amazonaws.com/${authConfig.userPoolId}`
  : ""

let userManager: UserManager | null = null

export function getUserManager(): UserManager | null {
  if (typeof window === "undefined" || !isAuthConfigured) {
    return null
  }

  if (!userManager) {
    userManager = new UserManager({
      authority,
      client_id: authConfig.clientId,
      redirect_uri: `${window.location.origin}/`,
      response_type: "code",
      scope: "openid email profile",
      userStore: new WebStorageStateStore({
        store: window.sessionStorage,
      }),
    })
  }

  return userManager
}

export async function getAccessToken(): Promise<string | null> {
  const manager = getUserManager()
  if (!manager) return null

  const user = await manager.getUser()

  if (!user || user.expired) {
    return null
  }

  return user.access_token
}

export async function signOutFromCognito(): Promise<void> {
  const manager = getUserManager()

  if (manager) {
    await manager.removeUser()
  }

  if (typeof window === "undefined") return

  if (!authConfig.domain || !authConfig.clientId) {
    return
  }

  const logoutUri = `${window.location.origin}/`
  const params = new URLSearchParams({
    client_id: authConfig.clientId,
    logout_uri: logoutUri,
  })

  window.location.assign(`https://${authConfig.domain}/logout?${params.toString()}`)
}
