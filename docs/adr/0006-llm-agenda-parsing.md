# ADR 0006: Agenda parsing with Amazon Nova on Bedrock

Status: Accepted. Date: 2026-10-29.

Context: Users paste multilingual, untrusted emails and notes into meeting forms. The existing API uses Aurora in a private VPC without NAT. Parsing must be optional, authenticated, inexpensive, and require human review.

Decision: Use configurable `PARSER_MODEL=amazon.nova-pro-v1:0` through boto3 Bedrock Converse, with one `record_agenda` tool and Pydantic validation. Retry invalid structured output once. Pass the user's date and IANA timezone. Never interpret vague times as exact timestamps. End of week means Friday under our working-week convention. Empty/non-agenda input produces a clear 422.

The 512 MB, 30-second parser Lambda runs outside the VPC, with no database credentials or database access. Cognito access-token verification precedes model invocation. Limit input to 10,000 characters. The browser reviews suggestions and saves through the existing authenticated meeting API. Store the original suggestion, model and prompt version alongside the final agenda as JSONB. Retain owner-scoped access checks.

Alternatives: Calling Bedrock from the API through a VPC interface endpoint adds approximately $7.30/month per endpoint/AZ before data charges and couples API availability to inference. Direct Claude API introduces a separate provider credential and billing path and does not match the chosen Amazon Nova model. Regular expressions alone are cheap but cannot reliably parse multilingual free text; use them only for narrow deterministic calendar corrections.

Consequences: Per-parse cost depends on tokens; configured Nova Pro rates are $0.80/M input and $3.20/M output. A 1,300-input / 150-output parse is approximately $0.00152. CloudWatch logs user id, model, prompt version, token counts, latency and estimated USD cost, without pasted text. IAM grants only model invocation and log access. If Bedrock fails or throttles, show a specific error and keep manual editing available. Cancel aborts the browser request; an already-running inference may still incur cost. A $5 monthly budget alert is configured when an email is supplied; this is an alert, not a spending cap.

Pricing reference: [AWS Nova Pro pricing presentation](https://d1.awsstatic.com/onedam/marketing-channels/website/aws/en_US/events/approved/reinvent-2025/reinvent/2024/slides/aim/AIM398-NEW_Practical-generative-AI-using-Amazon-Nova.pdf).
