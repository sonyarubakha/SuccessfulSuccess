# Lab 5 — Part 3, Step 7

## 1. Duplicate S3 events and email idempotency

Amazon S3 event notifications are delivered at least once. Therefore, the same
ObjectCreated notification can be delivered more than once.

I confirmed this behavior at the application level by generating the same weekly
report (`2026-W42`) twice. Both writes produced an S3 ObjectCreated event, and the
mailer Lambda sent two emails with the same report attached. CloudWatch showed
two separate `trigger=s3` invocations and two different SES message IDs.

To prevent accidental duplicate emails, I would store processed report identifiers
in DynamoDB and use a conditional PutItem before sending.

For duplicate delivery of the same S3 event, a key such as:

    bucket + object key + versionId

can be used. If S3 versioning is disabled, the S3 event sequencer can be included
instead.

If the product requirement is stronger — for example, "send at most one email for
each weekly report" even when `reports/2026-W42.csv` is overwritten — then
`bucket + object key` (or simply the ISO week) should be the idempotency key.

The DynamoDB write should use a condition such as attribute_not_exists(pk).
Only the invocation that successfully creates the record proceeds to SES.
A TTL can later remove old idempotency records.

## 2. NAT Gateway vs SES VPC endpoint vs split architecture

The report-builder Lambda must run inside the VPC because it accesses Aurora.
There are three possible ways to let the reporting workflow send email.

### NAT Gateway

A NAT Gateway would let the VPC Lambda reach the public SES API, but it introduces
a fixed hourly cost plus a per-GB processing cost.

Using the current AWS rate of approximately $0.045 per NAT Gateway-hour, one NAT
Gateway costs about:

    730 hours * $0.045 = $32.85/month

A public IPv4 address costs approximately another:

    730 hours * $0.005 = $3.65/month

Therefore, the fixed networking cost is approximately $36.50/month before data
processing. NAT Gateway data processing is approximately $0.045/GB.

### SES interface VPC endpoint

Amazon SES supports interface VPC endpoints through AWS PrivateLink, including API
access over port 443.

An interface endpoint is approximately $0.01 per endpoint-hour per Availability
Zone for the first pricing tier.

One AZ:

    730 * $0.01 = $7.30/month

Two AZs:

    2 * 730 * $0.01 = $14.60/month

PrivateLink also charges for processed data, approximately $0.01/GB in the first
pricing tier.

### Split architecture used in this project

The selected architecture separates the two responsibilities:

- report-builder runs inside the VPC, reads Aurora, and writes the CSV to S3
  through an S3 Gateway VPC endpoint;
- report-mailer runs outside the VPC and calls S3 and SES directly.

S3 Gateway endpoints have no hourly or data-processing charge. The mailer therefore
does not require either a NAT Gateway or an SES interface endpoint.

For around 10 reports per week, traffic is tiny and fixed infrastructure dominates:

    NAT Gateway:       about $36.50/month + data
    SES endpoint:      about $7.30/month for 1 AZ,
                       or $14.60/month for 2 AZs + data
    Split architecture: about $0 additional VPC networking cost

At a scale of one million emails per month, the same fixed costs remain, but the
per-GB processing component becomes more important:

    NAT:        ~$36.50/month + $0.045 per GB processed
    PrivateLink: ~$7.30/AZ/month + $0.01 per GB processed
    Split:       no NAT/PrivateLink processing layer for the mailer

SES email delivery itself is charged separately and is common to all three
architectures, so it does not change which networking architecture is cheaper.

For this workload, the split architecture is the simplest and most cost-effective:
the database-facing function remains private while the SES-facing function does not
need VPC internet connectivity.

AWS pricing references:
- https://aws.amazon.com/vpc/pricing/
- https://aws.amazon.com/privatelink/pricing/
- https://aws.amazon.com/ses/pricing/
- https://docs.aws.amazon.com/ses/latest/dg/send-email-set-up-vpc-endpoints.html

## 3. Why a one-week S3 presigned URL may expire early

An S3 presigned URL cannot remain valid longer than the credentials that were used
to sign it.

A Lambda function normally receives temporary IAM role credentials. Therefore,
even if the application requests a seven-day presigned URL expiration, the URL can
stop working when the Lambda's temporary credentials expire.

For a report link that must reliably remain available for one week, I would keep
the S3 bucket private and use a CloudFront signed URL with a seven-day expiration.
Its expiration is controlled by the CloudFront signature rather than by the
temporary Lambda execution-role credentials.

## 4. DLQ and redrive experiment

The report queue is configured with:

    maxReceiveCount = 3
    VisibilityTimeout = 360 seconds

For the experiment, I temporarily added an explicit Deny for `s3:PutObject` to the
builder role and temporarily shortened the queue visibility timeout.

A valid `2026-W42` message was sent to SQS. CloudWatch showed three failed Lambda
invocations with AccessDenied from S3. After the third failure, the message appeared
in the configured dead-letter queue.

I then removed the temporary Deny, restored the queue visibility timeout to
360 seconds, and started an SQS message move task from the DLQ back to the source
queue.

The redriven message was processed successfully:

    reports/2026-W42.csv

was written to S3, and the DLQ returned to zero messages.

This demonstrates that a failed report is retained after repeated failures and can
be safely redriven after the underlying problem is fixed.

## 5. Duplicate-email experiment

I invoked:

    make report-now WEEK=2026-W42

twice for the same week.

Both requests produced the same idempotent S3 object key:

    reports/2026-W42.csv

However, each PutObject generated an ObjectCreated notification. The mailer Lambda
was therefore invoked twice and SES successfully sent two emails.

This demonstrates why idempotent S3 object naming alone does not make the email
delivery step idempotent. A separate sent-event/idempotency store is needed if
duplicate emails must be prevented.
