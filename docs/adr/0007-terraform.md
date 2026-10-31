# ADR 0007: Adopt Auth, Reports and AI into HCP Terraform

Status: Accepted. Date: 2026-10-31.

## Context

Labs 4–6 introduced Cognito authentication, weekly reports and the AI agenda
parser as three CloudFormation stacks. Lab 7 consolidates that scope into a
Terraform root module with reviewed plans, reusable resource references and one
remote state. Existing Cognito users, client IDs, buckets, queue URLs, image
references and application behavior must survive the ownership transfer.

The network/API/database, frontend and ECR infrastructure predate this scope and
remain managed by CloudFormation. Terraform reads the shared backend stack's
outputs rather than adopting those resources. A broader rewrite would expand the
migration risk without being needed for this lab.

## Decision and migration

Manage Auth, Reports and AI in `infra/` using the AWS provider, with provider
v6.71.0 recorded in `.terraform.lock.hcl`. The translation preserves existing
resource names, identifiers, properties and applicable `PROJECT_NAME` tags. The
`aws.untagged` alias prevents default tags from changing the existing untagged
security-group ingress rule; it shares the default provider's AWS identity.

| Scope | Former CloudFormation resources | Terraform resources |
|---|---:|---:|
| Auth | 5 | 5 |
| Reports | 17 | 26 |
| AI | 7 | 9 |
| Total | 29 | 40 |

CloudFormation embeds some configurations inside larger resources. Terraform
models the Reports bucket's encryption, public-access settings, lifecycle and
notifications as four additional resources. Reports IAM inline policies and
managed-policy attachments add five resources; AI's inline policy and attachment
add two. These are configuration objects on existing AWS resources, not eleven
new infrastructure objects.

The handoff used both `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain`
on all 29 CloudFormation resources, including the existing conditional Google
identity provider and monthly budget. Retention updates were reviewed through
change sets and verified against deployed templates and unchanged physical IDs.
Conditional replacement indications for dependent references required additional
review of their underlying unchanged queue/function ARNs.

The three legacy stacks were removed with physical resources retained. Forty
declarative import definitions mapped the existing AWS objects to exact Terraform
addresses and provider-specific IDs. Import plans were corrected to remove
replacements and infrastructure updates before the import was approved. All 40
imports completed without AWS changes; the final state contains 40 managed
resources and a subsequent VCS-driven plan reported no changes. `imports.tf` was
then removed. Do not redeploy the historical `auth.yml`, `reports.yml` or `ai.yml`
templates or import the same objects into another state.

## Remote state and delivery

HCP Terraform organization `successfulsuccess-lab7-org`, project `Default Project`,
workspace `successfulsuccess-lab7` executes remotely and stores the authoritative
state. GitHub repository `dobosevych/SuccessfulSuccess`, branch `lab7`, is connected
with working directory `infra`. The migration baseline is commit `4bb3e1c`.

Infrastructure changes are reviewed in Git, pushed to the connected branch, and
planned by HCP. An authorized reviewer checks the exact commit and full plan before
manually confirming Apply. Auto-apply is disabled. Local Make commands may read
named public outputs but never apply Terraform changes. State locking and history
coordinate operations; access to runs and state remains restricted to authorized
users. Do not restore old state, move objects, or run competing local mutations as
part of routine application deployment.

Non-sensitive inputs are committed in `lab7.auto.tfvars`; local
`terraform.tfvars` remains ignored. Workspace Terraform variables hold sensitive
`db_password` and `google_client_secret`, plus private `report_recipients` and
`budget_email` values. Input sensitivity redacts normal presentation but does not
prevent secrets from being stored in state or plan data. Protect state access,
HCP tokens and logs, and avoid exposing raw state or unredacted plan JSON.

The added `report_queue_name` output demonstrates the delivery workflow: the
reviewed remote plan should show an output addition with zero AWS resource
changes. Manual Apply records that output in remote state without changing the
queue. The repository change itself does not update state.

## AWS authentication and operational boundaries

HCP uses AWS OIDC dynamic credentials (`TFC_AWS_PROVIDER_AUTH` and the workspace's
role ARN), rather than repository credentials. Trust binds `app.terraform.io`,
audience `aws.workload.identity`, the exact organization/project/workspace and
approved plan/apply phases. Both AWS provider configurations share this identity.
Local HCP output reads use Terraform CLI authentication; legacy CloudFormation
and application commands use separately configured local AWS credentials.

Least-privilege read permissions must cover provider refresh behavior, including
Lambda version enumeration, S3 configuration metadata, tag reads and the retained
backend CloudFormation data source. The read-only migration role is sufficient
for refresh and output-only changes, but future AWS modifications need separately
reviewed permissions. Do not broaden IAM automatically when a plan or apply fails.

Make now reads Auth/Reports/AI outputs from HCP, and the retired deployment targets
fail before they can recreate CloudFormation ownership. Backend, frontend and ECR
deployment remain CloudFormation/application workflows. Cognito redirects and
parser CORS changes require a reviewed Terraform run when frontend origins
change. On-demand report commands remain real operational actions that can send
email; they are not infrastructure smoke tests.

The shared backend provides the Reports database endpoint and networking. Shared
ECR images serve both ownership sets. The partial legacy `aws-destroy` therefore
only deletes the frontend and compatibility API; full teardown needs a separate
dependency review. It must not delete Cognito, the shared database/network or
registry behind Terraform's back.

An ECR lifecycle rule previously deleted an actively deployed Reports digest.
Automatic expiration was disabled through its CloudFormation owner, the exact
original image was restored from verified local cache, and both Reports Lambdas
were reactivated before migration completion. Preserve deployed image digests;
reintroduce cleanup only with a strategy that accounts for all consumers. Keeping
images indefinitely increases storage use.

## Risks and tradeoffs

- Split ownership is intentional but introduces dependencies between HCP and
  legacy CloudFormation. Changing backend outputs, security groups, image
  retention or frontend origins requires coordination.
- HCP adds an external service dependency for runs and state. Output-based Make
  commands also require HCP authentication and an initialized local cloud
  backend. A failed output read must stop deployment rather than use invented
  resource IDs.
- Cognito pool/client/branding and the reports bucket have `prevent_destroy`
  safeguards. They reject destructive plans while those resource blocks remain
  configured; they do not replace backups or protect resources removed from HCL.
- The imported public Cognito client has no secret. Its creation-only
  `generate_secret` argument is omitted because the provider imports it as null;
  explicitly setting false caused a replacement. Default token validity units
  are also omitted to preserve the provider's imported default representation.
- AWS-populated Google discovery fields have narrowly scoped ignores. They
  preserve service-maintained OAuth metadata without ignoring client ID, scopes
  or the whole provider-details map.
- Two **temporary migration-specific ignores** remain:
  `provider_details["client_secret"]` on the Google identity provider and
  `environment[0].variables["DATABASE_URL"]` on the builder Lambda. In run
  `run-3ssTttqscv5f77r7`, actual before/after values were identical with no unknown
  fields; only sensitivity annotations differed. Both sensitive input variables
  remain sensitive, with no literals or `nonsensitive()` workaround.
- Those two ignores can hide genuine changes, including credential rotations,
  database endpoint changes and URL changes. Review removal one field at a time:
  compare values privately, remove that entry, and inspect a new remote plan.
  Approve no AWS update merely to clear an annotation-only difference. If the
  artifact persists, investigate provider/Terraform behavior before changing
  state or weakening secret handling. Do not use blanket `ignore_changes = all`.

## References

- [HCP VCS-driven runs](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/run/ui)
- [AWS OIDC dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
- [Terraform lifecycle rules](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- [CloudFormation retention policies](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-attribute-deletionpolicy.html)
