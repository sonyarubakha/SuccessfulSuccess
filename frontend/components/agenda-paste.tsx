"use client"

import { useEffect, useRef, useState } from "react"
import { Loader2, Sparkles } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { ApiError, parseAgenda } from "@/lib/api"
import type { AgendaParseResponse } from "@/lib/types"

type AgendaPasteProps = {
  onParsed: (result: AgendaParseResponse) => void
  disabled?: boolean
}

export function AgendaPaste({ onParsed, disabled = false }: AgendaPasteProps) {
  const [text, setText] = useState("")
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const controllerRef = useRef<AbortController | null>(null)

  useEffect(() => {
    return () => controllerRef.current?.abort()
  }, [])

  async function handleParse() {
    if (!text.trim() || loading) return

    const controller = new AbortController()
    controllerRef.current = controller
    setLoading(true)
    setError(null)

    try {
      const result = await parseAgenda(text, controller.signal)

      if (!controller.signal.aborted) {
        onParsed(result)
      }
    } catch (err) {
      if (controller.signal.aborted) return

      setError(
        err instanceof ApiError
          ? err.message
          : "Could not parse the agenda. Please try again.",
      )
    } finally {
      if (controllerRef.current === controller) {
        controllerRef.current = null
        setLoading(false)
      }
    }
  }

  function handleCancel() {
    controllerRef.current?.abort()
    controllerRef.current = null
    setLoading(false)
  }

  return (
    <section className="space-y-3 rounded-lg border p-4">
      <div className="flex items-center gap-2">
        <Sparkles className="size-4" aria-hidden />
        <Label htmlFor="agenda-paste-text" className="font-semibold">
          Paste an agenda
        </Label>
      </div>

      <p className="text-muted-foreground text-sm">
        Paste meeting notes or an email. AI will suggest meeting details,
        agenda topics and action items for you to review.
      </p>

      <Textarea
        id="agenda-paste-text"
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder="Monday 10:00, pricing sync, 45 minutes. Discuss new tariffs..."
        rows={5}
        maxLength={10000}
        disabled={disabled || loading}
      />

      <p className="text-muted-foreground text-right text-xs">
        {text.length}/10000 characters
      </p>

      {error && (
        <p role="alert" className="text-destructive text-sm">
          {error}
        </p>
      )}

      <div className="flex gap-2">
        <Button
          type="button"
          onClick={handleParse}
          disabled={disabled || loading || !text.trim()}
        >
          {loading ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null}
          {loading ? "Parsing..." : "Parse"}
        </Button>

        {loading && (
          <Button type="button" variant="outline" onClick={handleCancel}>
            Cancel
          </Button>
        )}
      </div>

      <p className="text-muted-foreground text-xs">
        AI suggestions are not saved until you review and submit the meeting.
      </p>
    </section>
  )
}
