"use client"

import { useState } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import type { ActionItem, AgendaItem, MeetingAgenda } from "@/lib/types"

type Props = {
  initial: MeetingAgenda | null
  suggested?: boolean
  onChange: (agenda: MeetingAgenda) => void
}

export function AgendaEditor({ initial, suggested = false, onChange }: Props) {
  const [agenda, setAgenda] = useState<MeetingAgenda>(
    initial ?? { items: [], action_items: [] },
  )
  const [suggestedItems, setSuggestedItems] = useState(
    agenda.items.map(() => suggested),
  )
  const [suggestedActions, setSuggestedActions] = useState(
    agenda.action_items.map(() => suggested),
  )

  function commit(next: MeetingAgenda) {
    setAgenda(next)
    onChange(next)
  }

  function changeItem(index: number, item: AgendaItem) {
    commit({
      ...agenda,
      items: agenda.items.map((current, i) => (i === index ? item : current)),
    })
    setSuggestedItems((flags) =>
      flags.map((flag, i) => (i === index ? false : flag)),
    )
  }

  function changeAction(index: number, action: ActionItem) {
    commit({
      ...agenda,
      action_items: agenda.action_items.map((current, i) =>
        i === index ? action : current,
      ),
    })
    setSuggestedActions((flags) =>
      flags.map((flag, i) => (i === index ? false : flag)),
    )
  }

  return (
    <section className="space-y-5 rounded-lg border p-4">
      <h3 className="font-semibold">Agenda</h3>

      <div className="space-y-3">
        <h4 className="text-sm font-medium">Agenda items</h4>

        {agenda.items.map((item, index) => (
          <div key={index} className="space-y-2 rounded-md border p-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium">
                Topic {index + 1}
                {suggestedItems[index] && (
                  <span className="text-muted-foreground ml-2">Suggested</span>
                )}
              </span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                aria-label={`Remove topic ${index + 1}`}
                onClick={() => {
                  commit({
                    ...agenda,
                    items: agenda.items.filter((_, i) => i !== index),
                  })
                  setSuggestedItems((flags) => flags.filter((_, i) => i !== index))
                }}
              >
                <Trash2 className="size-4" aria-hidden />
              </Button>
            </div>

            <Input
              aria-label={`Topic ${index + 1}`}
              placeholder="Topic"
              value={item.topic}
              onChange={(event) =>
                changeItem(index, { ...item, topic: event.target.value })
              }
            />

            <div className="grid grid-cols-2 gap-2">
              <Input
                aria-label={`Topic ${index + 1} owner`}
                placeholder="Owner (optional)"
                value={item.owner ?? ""}
                onChange={(event) =>
                  changeItem(index, { ...item, owner: event.target.value || null })
                }
              />
              <Input
                aria-label={`Topic ${index + 1} minutes`}
                type="number"
                min={1}
                placeholder="Minutes"
                value={item.minutes ?? ""}
                onChange={(event) =>
                  changeItem(index, {
                    ...item,
                    minutes: event.target.value ? Number(event.target.value) : null,
                  })
                }
              />
            </div>
          </div>
        ))}

        <Button
          type="button"
          variant="outline"
          disabled={agenda.items.length >= 50}
          onClick={() => {
            commit({
              ...agenda,
              items: [...agenda.items, { topic: "", owner: null, minutes: null }],
            })
            setSuggestedItems((flags) => [...flags, false])
          }}
        >
          <Plus className="size-4" aria-hidden />
          Add agenda item
        </Button>
      </div>

      <div className="space-y-3">
        <h4 className="text-sm font-medium">Action items</h4>

        {agenda.action_items.map((action, index) => (
          <div key={index} className="space-y-2 rounded-md border p-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium">
                Action {index + 1}
                {suggestedActions[index] && (
                  <span className="text-muted-foreground ml-2">Suggested</span>
                )}
              </span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                aria-label={`Remove action ${index + 1}`}
                onClick={() => {
                  commit({
                    ...agenda,
                    action_items: agenda.action_items.filter((_, i) => i !== index),
                  })
                  setSuggestedActions((flags) => flags.filter((_, i) => i !== index))
                }}
              >
                <Trash2 className="size-4" aria-hidden />
              </Button>
            </div>

            <Input
              aria-label={`Action ${index + 1} task`}
              placeholder="Task"
              value={action.task}
              onChange={(event) =>
                changeAction(index, { ...action, task: event.target.value })
              }
            />

            <div className="grid grid-cols-2 gap-2">
              <Input
                aria-label={`Action ${index + 1} owner`}
                placeholder="Owner (optional)"
                value={action.owner ?? ""}
                onChange={(event) =>
                  changeAction(index, {
                    ...action,
                    owner: event.target.value || null,
                  })
                }
              />
              <Input
                aria-label={`Action ${index + 1} due date`}
                type="date"
                value={action.due ?? ""}
                onChange={(event) =>
                  changeAction(index, {
                    ...action,
                    due: event.target.value || null,
                  })
                }
              />
            </div>
          </div>
        ))}

        <Button
          type="button"
          variant="outline"
          disabled={agenda.action_items.length >= 50}
          onClick={() => {
            commit({
              ...agenda,
              action_items: [
                ...agenda.action_items,
                { task: "", owner: null, due: null },
              ],
            })
            setSuggestedActions((flags) => [...flags, false])
          }}
        >
          <Plus className="size-4" aria-hidden />
          Add action item
        </Button>
      </div>
    </section>
  )
}
