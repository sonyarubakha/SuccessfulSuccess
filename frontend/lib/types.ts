// Mirrors the Pydantic schemas in backend/app/schemas/meeting.py.

export type Participant = {
  id: string
  name: string
  email: string | null
  position: number
}

export type AgendaItem = {
  topic: string
  owner: string | null
  minutes: number | null
}

export type ActionItem = {
  task: string
  owner: string | null
  due: string | null
}

export type MeetingAgenda = {
  items: AgendaItem[]
  action_items: ActionItem[]
}

export type ParsedAgenda = MeetingAgenda & {
  title: string | null
  starts_at: string | null
  duration_minutes: number | null
  language: string
}

export type AiSuggestionRecord = {
  agenda: ParsedAgenda
  model: string
  prompt_version: string
}

export type AgendaParseResponse = {
  agenda: ParsedAgenda
  model: string
  prompt_version: string
  usage: {
    input_tokens: number
    output_tokens: number
  }
  latency_ms: number
  cost_usd: number
}

export type Meeting = {
  id: string
  name: string
  description: string | null
  location: string | null
  starts_at: string
  ends_at: string
  participants: Participant[]
  agenda: MeetingAgenda | null
  ai_suggestion: AiSuggestionRecord | null
  created_at: string
  updated_at: string
}

export type MeetingList = {
  items: Meeting[]
  total: number
  limit: number
  offset: number
  date: string
}

export type ParticipantInput = {
  name: string
  email?: string | null
}

export type MeetingCreateInput = {
  name: string
  description?: string | null
  location?: string | null
  starts_at: string
  ends_at: string
  participants: ParticipantInput[]
  agenda?: MeetingAgenda | null
  ai_suggestion?: AiSuggestionRecord | null
}

export type ApiErrorDetail = {
  field: string
  message: string
}

export type ApiErrorBody = {
  error: {
    code: string
    message: string
    details: ApiErrorDetail[]
  }
}

export type UserProfile = {
  id: string
  email: string | null
  email_verified: boolean
  name: string | null
  given_name: string | null
  family_name: string | null
  picture_url: string | null
  auth_provider: string
  created_at: string
  updated_at: string
  last_login_at: string | null
}
