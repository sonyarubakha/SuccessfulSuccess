import { getAccessToken, signOutFromCognito } from "@/lib/auth"
import type {
  ApiErrorBody,
  ApiErrorDetail,
  AgendaParseResponse,
  Meeting,
  MeetingCreateInput,
  MeetingList,
  UserProfile,
} from "@/lib/types"

export const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000"

export class ApiError extends Error {
  readonly code: string
  readonly details: ApiErrorDetail[]
  readonly status: number

  constructor(status: number, code: string, message: string, details: ApiErrorDetail[]) {
    super(message)
    this.name = "ApiError"
    this.status = status
    this.code = code
    this.details = details
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await getAccessToken()
  let response: Response
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init?.headers,
      },
      cache: "no-store",
    })
  } catch {
    throw new ApiError(0, "network_error", "Could not reach the meetings API.", [])
  }

  // The session is gone or was revoked: sign out, and the auth guard sends the
  // user back to the login page.
  if (response.status === 401) {
    void signOutFromCognito()
  }

  if (response.status === 204) {
    return undefined as T
  }

  const text = await response.text()
  const payload = text ? JSON.parse(text) : null

  if (!response.ok) {
    const body = payload as ApiErrorBody | null
    throw new ApiError(
      response.status,
      body?.error?.code ?? "internal_error",
      body?.error?.message ?? `Request failed with status ${response.status}.`,
      body?.error?.details ?? [],
    )
  }

  return payload as T
}

export function listMeetings(params: { date?: string; q?: string } = {}) {
  const search = new URLSearchParams()
  if (params.date) search.set("date", params.date)
  if (params.q) search.set("q", params.q)
  const query = search.toString()
  return request<MeetingList>(`/api/v1/meetings${query ? `?${query}` : ""}`)
}

export function getMeeting(id: string) {
  return request<Meeting>(`/api/v1/meetings/${id}`)
}

export function createMeeting(payload: MeetingCreateInput) {
  return request<Meeting>("/api/v1/meetings", {
    method: "POST",
    body: JSON.stringify(payload),
  })
}

export function updateMeeting(id: string, payload: MeetingCreateInput) {
  return request<Meeting>(`/api/v1/meetings/${id}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  })
}

export function deleteMeeting(id: string) {
  return request<void>(`/api/v1/meetings/${id}`, { method: "DELETE" })
}

export function getMe() {
  return request<UserProfile>("/api/v1/me")
}

/** Stores the profile from the ID token in the users table; call after signing in. */
export function syncMe(idToken: string) {
  return request<UserProfile>("/api/v1/me/sync", {
    method: "POST",
    body: JSON.stringify({ id_token: idToken }),
  })
}

export function requestCurrentReport() {
  return request<{ status: string; week: string }>("/api/v1/reports/current", {
    method: "POST",
  })
}

/** Parse pasted text with the separate Bedrock Lambda; never writes to the database. */
export async function parseAgenda(
  text: string,
  signal?: AbortSignal,
): Promise<AgendaParseResponse> {
  const url = process.env.NEXT_PUBLIC_AI_PARSER_URL
  if (!url) {
    throw new ApiError(0, "parser_not_configured", "AI parser URL is not configured.", [])
  }

  const token = await getAccessToken()
  if (!token) {
    throw new ApiError(401, "unauthorized", "Sign in to parse an agenda.", [])
  }

  if (signal?.aborted) {
    throw new DOMException("Parsing canceled.", "AbortError")
  }

  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Kyiv"
  const dateParts = Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date())
  const part = (type: string) => dateParts.find((p) => p.type === type)?.value ?? ""
  const today = `${part("year")}-${part("month")}-${part("day")}`

  let response: Response
  try {
    response = await fetch(url, {
      method: "POST",
      signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ text, today, tz }),
    })
  } catch (error) {
    if (signal?.aborted) throw error
    throw new ApiError(0, "network_error", "Could not reach the AI parser.", [])
  }

  if (response.status === 401) {
    void signOutFromCognito()
  }

  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    const body = payload as ApiErrorBody | null
    throw new ApiError(
      response.status,
      body?.error?.code ?? "parser_error",
      body?.error?.message ?? `AI parsing failed (${response.status}).`,
      body?.error?.details ?? [],
    )
  }

  if (!payload) {
    throw new ApiError(502, "invalid_response", "AI parser returned an empty response.", [])
  }

  return payload as AgendaParseResponse
}
