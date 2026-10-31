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

## Alternatives

| Tool | Why or why not for this project |
|---|---|
| Terraform | Chosen for declarative imports, explicit plans, references/modules and the required HCP VCS workflow. Its provider model also leaves room for future GitHub, OAuth or DNS integration; this migration manages only the selected AWS scope. We accept responsibility for state security and provider/default differences. |
| CloudFormation | Already works and keeps stack state in AWS, with change sets and rollback behavior. It remains appropriate for the older stacks. Keeping everything there would avoid this migration, but would not meet the lab's Terraform/HCP workflow objective. |
| AWS CDK | Offers reusable infrastructure in general-purpose languages, but synthesizes CloudFormation and retains its stack-based deployment model. It adds a language/build layer without providing the chosen Terraform state/import workflow. |
| OpenTofu | A viable open-source alternative with providers, HCL and a plan/state workflow. This lab standardizes on Terraform and HCP; changing engines and run platform during adoption would expand compatibility and operational review. Reconsider separately if licensing, governance or platform independence becomes a priority. |

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
then removed. The three migrated CloudFormation templates are deleted from the
working tree as required by Part 2, Step 3; their source and retention changes
remain available in Git history. Do not recreate their stacks or import the same
objects into another state. All other CloudFormation templates remain in place.
Template names retained in HCL comments and the budget-variable description are
historical provenance, not file dependencies; the Terraform files are unchanged
by this cleanup.

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

### Who may change infrastructure

Repository contributors may propose HCL/input changes in a branch and pull
request. A maintainer reviews the intended resource effects before changes reach
the connected `lab7` branch; an HCP user with apply permission reviews the exact
VCS plan and manually approves it. Read/plan access alone does not authorize an
apply. Organization/workspace administrators control membership, variable access
and OIDC trust; those changes need separate review. This is the operating policy,
not a claim that branch protections or separation of duties were audited here.

GitHub Actions' application role releases the legacy API code; it does not own
Auth/Reports/AI infrastructure. For changes requiring both roads, apply compatible
infrastructure first, then release code, with staged updates for breaking changes.
The two workflows have no automatic dependency gate. Emergency console changes
need explicit authorization, an incident record and matching reviewed HCL before
the next reconciliation; do not blindly revert an intentional emergency fix.

Non-sensitive inputs are committed in `lab7.auto.tfvars`; local
`terraform.tfvars` remains ignored. Workspace Terraform variables hold sensitive
`db_password` and `google_client_secret`, plus private `report_recipients` and
`budget_email` values. Input sensitivity redacts normal presentation but does not
prevent secrets from being stored in state or plan data. Protect state access,
HCP tokens and logs, and avoid exposing raw state or unredacted plan JSON.
The configured Google secret also exists in Cognito's identity-provider settings;
the builder's database URL contains the password in Lambda environment settings.
Provider refresh can read these into memory, plan artifacts and remote state.
Restrict AWS configuration-read permissions as well as HCP access. Do not enable
debug logging or echo secret variables in CI; sensitivity is not encryption and
does not protect arbitrary application or provider log messages.

The completed `report_queue_name` demonstration used a GitHub-triggered HCP run
and manual Apply to record the output in remote state without changing the queue
or other AWS resources. The following plan reported no changes. Preserve the run
screenshot and plan output as submission evidence; the repository itself does
not prove which remote run was approved.

### HCP Terraform outage

Deployed AWS resources continue running without HCP; application runtime does
not read Terraform state. New remote plans, approvals, applies and state/output
reads may be unavailable. Make commands that require HCP outputs stop, while
independent legacy application operations may still work with their existing AWS
credentials and permissions. Do not substitute stale output values silently.

Pause infrastructure changes and wait for service recovery. If a run was
interrupted, inspect its status, lock and actual AWS effects before starting a
new plan; an apply may have completed some operations. Never force-unlock an
active run, initialize a competing local state, or import the same objects to
bypass the outage. Prolonged-outage recovery requires a separately authorized
procedure using a protected, verified state version, exclusive ownership,
credential controls and reconciliation. No alternate backend or automatic
failover is configured in this project.

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
- [AWS CDK and CloudFormation](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [OpenTofu overview](https://opentofu.org/docs/intro/)
