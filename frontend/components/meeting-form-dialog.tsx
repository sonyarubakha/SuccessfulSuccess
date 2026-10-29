"use client"

import { zodResolver } from "@hookform/resolvers/zod"
import { CalendarIcon } from "lucide-react"
import { useEffect, useState } from "react"
import { Controller, useForm } from "react-hook-form"
import { toast } from "sonner"
import { z } from "zod"

import { AgendaEditor } from "@/components/agenda-editor"
import { AgendaPaste } from "@/components/agenda-paste"
import { ParticipantsInput } from "@/components/participants-input"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Textarea } from "@/components/ui/textarea"
import { useCreateMeeting, useUpdateMeeting } from "@/hooks/use-meetings"
import { ApiError } from "@/lib/api"
import { formatTime, parseIsoDay, toIsoDate, toIsoWithOffset } from "@/lib/datetime"
import type { AgendaParseResponse, AiSuggestionRecord, Meeting, MeetingAgenda } from "@/lib/types"

const timePattern = /^([01]\d|2[0-3]):([0-5]\d)$/

const participantSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(120, "Name is too long"),
  email: z
    .string()
    .trim()
    .max(255)
    .refine((value) => value === "" || z.email().safeParse(value).success, {
      message: "Enter a valid email address",
    })
    .optional(),
})

const formSchema = z
  .object({
    name: z.string().trim().min(1, "Name is required").max(200, "Name is too long"),
    description: z.string().trim().max(2000, "Description is too long").optional(),
    location: z.string().trim().max(200, "Location is too long").optional(),
    date: z.date(),
    startTime: z.string().regex(timePattern, "Use HH:mm"),
    endTime: z.string().regex(timePattern, "Use HH:mm"),
    participants: z.array(participantSchema).max(50, "At most 50 participants"),
  })
  .refine((data) => data.endTime > data.startTime, {
    message: "The meeting must end after it starts",
    path: ["endTime"],
  })
  .refine(
    (data) => {
      const keys = data.participants.map(
        (p) => `${p.name.trim().toLowerCase()}|${(p.email ?? "").trim().toLowerCase()}`,
      )
      return new Set(keys).size === keys.length
    },
    { message: "Participants must be unique", path: ["participants"] },
  )

type FormValues = z.infer<typeof formSchema>

type ParticipantErrors = { name?: { message?: string }; email?: { message?: string } }

/** Flattens react-hook-form's per-row participant errors into { rowIndex: message }. */
function participantErrors(rows: unknown): Record<number, string | undefined> {
  if (!Array.isArray(rows)) return {}
  return Object.fromEntries(
    rows.map((row: ParticipantErrors | undefined, index: number) => [
      index,
      row?.name?.message ?? row?.email?.message,
    ]),
  )
}

/** Blank form for a new meeting, or the meeting's current values when editing. */
function defaultValues(meeting?: Meeting): FormValues {
  if (!meeting) {
    return {
      name: "",
      description: "",
      location: "",
      date: new Date(),
      startTime: "10:00",
      endTime: "11:00",
      participants: [{ name: "", email: "" }],
    }
  }
  return {
    name: meeting.name,
    description: meeting.description ?? "",
    location: meeting.location ?? "",
    date: parseIsoDay(meeting.starts_at),
    startTime: formatTime(meeting.starts_at),
    endTime: formatTime(meeting.ends_at),
    participants:
      meeting.participants.length > 0
        ? meeting.participants.map((p) => ({ name: p.name, email: p.email ?? "" }))
        : [{ name: "", email: "" }],
  }
}

/** Creates a meeting, or edits `meeting` when one is passed. */
export function MeetingFormDialog({
  open,
  onOpenChange,
  meeting,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  meeting?: Meeting
}) {
  const createMeeting = useCreateMeeting()
  const updateMeeting = useUpdateMeeting()
  const [datePickerOpen, setDatePickerOpen] = useState(false)
  const [editedAgenda, setEditedAgenda] = useState<MeetingAgenda | null>(null)
  const [aiSuggestion, setAiSuggestion] = useState<AiSuggestionRecord | null>(null)
  const [agendaEditorVersion, setAgendaEditorVersion] = useState(0)
  const [suggestedFields, setSuggestedFields] = useState<Set<string>>(new Set())
  function clearSuggestion(field: string) {
    setSuggestedFields((current) => {
      const next = new Set(current)
      next.delete(field)
      return next
    })
  }
  function suggestion(field: string) {
    return suggestedFields.has(field) ? <span className="text-muted-foreground ml-2 text-xs">Suggested</span> : null
  }
  const isEdit = !!meeting

  const form = useForm<FormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: defaultValues(meeting),
  })

  const {
    register,
    handleSubmit,
    control,
    reset,
    setError,
    formState: { errors, isSubmitting },
  } = form

  // Refill the form each time it opens, so edits start from the meeting's current values.
  useEffect(() => {
    if (open) {
      reset(defaultValues(meeting))
      // Reset local draft state when the dialog opens, alongside react-hook-form.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setEditedAgenda(meeting?.agenda ?? null)
      setAiSuggestion(meeting?.ai_suggestion ?? null)
      setSuggestedFields(new Set())
      setAgendaEditorVersion((version) => version + 1)
    }
  }, [open, meeting, reset])

  function handleAgendaParsed(result: AgendaParseResponse) {
    const parsed = result.agenda
    setSuggestedFields(new Set([
      ...(parsed.title ? ["name"] : []),
      ...(parsed.starts_at ? ["date", "startTime"] : []),
      ...(parsed.starts_at && parsed.duration_minutes ? ["endTime"] : []),
    ]))

    setEditedAgenda({
      items: parsed.items.map((item) => ({ ...item })),
      action_items: parsed.action_items.map((item) => ({ ...item })),
    })

    setAiSuggestion({
      agenda: parsed,
      model: result.model,
      prompt_version: result.prompt_version,
    })

    // Remount the editor to show the new suggestions and their flags.
    setAgendaEditorVersion((version) => version + 1)

    if (parsed.title) {
      form.setValue("name", parsed.title, { shouldDirty: true })
    }

    if (parsed.starts_at) {
      const match = parsed.starts_at.match(
        /^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2})/,
      )

      if (match) {
        const hours = Number(match[1])
        const minutes = Number(match[2])

        form.setValue("date", parseIsoDay(parsed.starts_at), {
          shouldDirty: true,
        })
        form.setValue("startTime", `${match[1]}:${match[2]}`, {
          shouldDirty: true,
        })

        if (parsed.duration_minutes != null) {
          const endMinutes = hours * 60 + minutes + parsed.duration_minutes

          if (endMinutes < 1440) {
            const endHour = String(Math.floor(endMinutes / 60)).padStart(2, "0")
            const endMinute = String(endMinutes % 60).padStart(2, "0")
            form.setValue("endTime", `${endHour}:${endMinute}`, {
              shouldDirty: true,
            })
          } else {
            toast.warning("Review the meeting end time: it crosses midnight.")
          }
        }
      }
    }

    toast.success("Agenda parsed. Review the suggestions before saving.")
  }

  const onSubmit = handleSubmit(async (values) => {
    const participants = values.participants
      .filter((participant) => participant.name.trim() !== "")
      .map((participant) => ({
        name: participant.name.trim(),
        email: participant.email?.trim() ? participant.email.trim() : null,
      }))

    const payload = {
      name: values.name.trim(),
      description: values.description?.trim() || null,
      location: values.location?.trim() || null,
      starts_at: toIsoWithOffset(values.date, values.startTime),
      ends_at: toIsoWithOffset(values.date, values.endTime),
      participants,
      agenda: editedAgenda,
      ai_suggestion: aiSuggestion,
    }

    try {
      if (meeting) {
        await updateMeeting.mutateAsync({ id: meeting.id, payload })
        toast.success("Meeting updated")
      } else {
        await createMeeting.mutateAsync(payload)
        toast.success("Meeting created")
      }
      onOpenChange(false)
    } catch (error) {
      if (error instanceof ApiError) {
        // Map server-side field errors back onto the matching inputs.
        const fieldMap: Record<string, keyof FormValues> = {
          name: "name",
          description: "description",
          location: "location",
          starts_at: "startTime",
          ends_at: "endTime",
          participants: "participants",
        }
        for (const detail of error.details) {
          const target = fieldMap[detail.field.split(".")[0] ?? ""]
          if (target) setError(target, { message: detail.message })
        }
        toast.error(error.message)
      } else {
        toast.error(isEdit ? "Could not update the meeting." : "Could not create the meeting.")
      }
    }
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90svh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit meeting" : "New meeting"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Change the details, time slot or participants."
              : "Give it a name, a time slot and the people who should be there."}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={onSubmit} className="space-y-4">
          <AgendaPaste onParsed={handleAgendaParsed} disabled={isSubmitting} />

          <AgendaEditor
            key={agendaEditorVersion}
            initial={editedAgenda}
            suggested={!!aiSuggestion}
            onChange={setEditedAgenda}
          />
          <div className="space-y-2">
            <Label htmlFor="name">Name {suggestion("name")}</Label>
            <Input
              id="name"
              placeholder="Sprint planning"
              aria-invalid={!!errors.name}
              aria-describedby={errors.name ? "name-error" : undefined}
              {...register("name", { onChange: () => clearSuggestion("name") })}
            />
            {errors.name ? (
              <p id="name-error" className="text-destructive text-sm">
                {errors.name.message}
              </p>
            ) : null}
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">Description</Label>
            <Textarea
              id="description"
              rows={3}
              placeholder="What is this meeting about?"
              {...register("description")}
            />
            {errors.description ? (
              <p className="text-destructive text-sm">{errors.description.message}</p>
            ) : null}
          </div>

          <div className="space-y-2">
            <Label htmlFor="location">Location</Label>
            <Input id="location" placeholder="Room 3 or a meeting link" {...register("location")} />
          </div>

          <div className="grid gap-4 sm:grid-cols-3">
            <div className="space-y-2 sm:col-span-1">
              <Label>Date {suggestion("date")}</Label>
              <Controller
                control={control}
                name="date"
                render={({ field }) => (
                  <Popover open={datePickerOpen} onOpenChange={setDatePickerOpen}>
                    <PopoverTrigger asChild>
                      <Button
                        type="button"
                        variant="outline"
                        className="w-full justify-start font-normal"
                      >
                        <CalendarIcon className="size-4" aria-hidden />
                        {toIsoDate(field.value)}
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-auto p-0" align="start">
                      <Calendar
                        mode="single"
                        selected={field.value}
                        onSelect={(date) => {
                          if (date) { field.onChange(date); clearSuggestion("date") }
                          setDatePickerOpen(false)
                        }}
                        autoFocus
                      />
                    </PopoverContent>
                  </Popover>
                )}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="startTime">Start {suggestion("startTime")}</Label>
              <Input id="startTime" type="time" step={900} {...register("startTime", { onChange: () => clearSuggestion("startTime") })} />
              {errors.startTime ? (
                <p className="text-destructive text-sm">{errors.startTime.message}</p>
              ) : null}
            </div>

            <div className="space-y-2">
              <Label htmlFor="endTime">End {suggestion("endTime")}</Label>
              <Input id="endTime" type="time" step={900} {...register("endTime", { onChange: () => clearSuggestion("endTime") })} />
              {errors.endTime ? (
                <p className="text-destructive text-sm">{errors.endTime.message}</p>
              ) : null}
            </div>
          </div>

          <Controller
            control={control}
            name="participants"
            render={({ field }) => (
              <ParticipantsInput
                value={field.value}
                onChange={field.onChange}
                errors={participantErrors(errors.participants)}
              />
            )}
          />
          {errors.participants?.message ? (
            <p className="text-destructive text-sm">{errors.participants.message}</p>
          ) : null}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={isSubmitting}>
              {isEdit
                ? isSubmitting
                  ? "Saving…"
                  : "Save changes"
                : isSubmitting
                  ? "Creating…"
                  : "Create meeting"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
