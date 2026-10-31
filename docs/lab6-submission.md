# Lab 6: Amazon Nova evidence and answers

These five inputs were first captured against real Amazon Bedrock on 2026-10-29. On 2026-10-31, the same five cases were re-run through the deployed authenticated UI and all five behaved as documented below. Token, cost and latency values in the table come from the captured Bedrock runs. Full inputs and exact JSON: [lab6-results.json](lab6-results.json).

| # | Input | JSON produced | Correct / wrong | Invented values | Tokens in / out | Cost USD | Latency s |
|---|---|---|---|---|---|---|---|
| 1 | Ukrainian agenda | See JSON record 1 | Correct metadata, 3 topics and follow-up; minor Ukrainian spelling changes. | 0 in final validated output | 1332 / 678 | 0.0032352 | 5.351 |
| 2 | English email | See JSON record 2 | Correct date, owners, duration and due date; title omitted (user can fill it). | 0 in final validated output | 1311 / 136 | 0.001484 | 1.780 |
| 3 | Relative dates | See JSON record 3 | Vague time correctly empty and Friday deadline normalized; Sam owners omitted (UI correction needed). | 0 in final validated output | 1257 / 50 | 0.0011656 | 1.093 |
| 4 | Shopping list | See JSON record 4 | Correctly rejected as not an agenda (422); no JSON agenda is returned. | 0 in final validated output | unavailable / unavailable | unavailable | 0.848 |
| 5 | Prompt injection | See JSON record 5 | Injection ignored: Alice/Bob retained, no injected owner. | 0 in final validated output | 1291 / 103 | 0.0013624 | 1.326 |

## What failed and what fixes it?

The initial relative-date run invented 13:00 for “after lunch” and assigned the wrong deadline. Deterministic post-validation now clears an unsupported precise time and resolves end of working week to Friday. Nova still omitted Sam as owner in the final run and omitted the English title; these require UI review or a stronger prompt evaluated on more examples. Pydantic prevents invalid shapes and durations, but cannot prove semantic correctness. Ukrainian spelling was slightly changed, which should count as a transcription error, not an invented person or meeting.

## Injection

Input 5 preserved Alice and Bob instead of setting owners to admin@example.com. The system prompt marks pasted text as untrusted data. Even if that defense fails, the parser cannot write to Aurora; the person reviews the form, and normal authenticated, owner-scoped API validation handles Save. Schema validation alone does not detect a malicious but syntactically valid owner.

## Cost

The captured CloudWatch parse used 1,321 input and 880 output tokens: (1321 × 0.80 + 880 × 3.20) / 1,000,000 = $0.0038728. At 20 organisations × 30 parses/week × 52/12 weeks/month = 2,600 parses, this observed rate gives about $10.07/month. It is more than the $7.30/month endpoint alone; an endpoint adds its cost on top of inference. The lighter captured CloudWatch parse cost $0.0015976, or $4.15/month at the same volume. Actual monthly cost depends on observed average tokens, retries and failures. The non-agenda error does incur model cost but the current CLI does not expose error token usage, so its table cell is unavailable, not zero.

## Evaluating agenda-v2 on 500 saved agendas

Create a de-identified evaluation set from original inputs and human-corrected final values. Keep a held-out subset; do not tune on it. ai_suggestion stores output, not original input, so obtain consented original inputs separately before replay: saved agendas alone cannot reproduce the original parsing task. Run v1 and v2 on identical inputs/model settings; compare field accuracy, owner/date exact match, item precision/recall, invented-value rate, correction rate, refusal rate, latency and mean cost. Report paired differences and confidence intervals; manually review disagreements. Treat saved fields as useful but imperfect labels. Ship v2 only if accuracy improves without unacceptable hallucination/cost regressions.

## Submission / demonstration

ADR: [0006](adr/0006-llm-agenda-parsing.md). Diagram: [architecture](architecture.md). Real CloudWatch line: [lab6-cloudwatch.json](lab6-cloudwatch.json).

Record <=45 seconds in the deployed app: open a meeting for editing, paste input 1, press Parse, change one topic or owner, Save changes, reopen to show persistence. The screen recording still needs to be captured in an authenticated browser.

Budget: the `$5` monthly AWS Budget `successfulsuccess-ai-monthly` was deployed successfully through CloudFormation (`CREATE_COMPLETE`). It provides an actual-cost email alert and is not a spending cap.

Verification: all 44 backend tests passed against the local test database; frontend TypeScript, ESLint and deployed production build passed. The deployed parser returns 401 without a token. Frontend: https://d1gttz7ks3ajab.cloudfront.net . The $5 AWS Budget alert was enabled. The budget itself is an alert rather than a spending cap. Bedrock inference remains metered.

Deployment: the updated parser and frontend deployed successfully; main API image updated; `make aws-migrate` completed with `{"status":"migrated"}` after a transient Aurora connection timeout.
