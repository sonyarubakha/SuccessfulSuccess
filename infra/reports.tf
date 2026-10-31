# reports.yml: ReportBucket, with its existing settings split into provider resources.
resource "aws_s3_bucket" "reports" {
  bucket        = "${var.project_name}-reports-${var.aws_account_id}"
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    id     = "DeleteOldReports"
    status = "Enabled"
    filter {
      prefix = "reports/"
    }
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }
  depends_on = [aws_lambda_permission.mailer]
}

# reports.yml: ReportDeadLetterQueue, ReportQueue
resource "aws_sqs_queue" "report_dlq" {
  name                      = "${var.project_name}-report-dlq"
  max_message_size          = 1048576
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "reports" {
  name                       = "${var.project_name}-report-queue"
  max_message_size           = 1048576
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = 360
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.report_dlq.arn
    maxReceiveCount     = 3
  })
}

# reports.yml: S3GatewayEndpoint, SqsEndpointSelfIngress, SqsInterfaceEndpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = var.route_table_ids
}

resource "aws_vpc_security_group_ingress_rule" "sqs_self" {
  provider                     = aws.untagged
  security_group_id            = var.function_security_group_id
  referenced_security_group_id = var.function_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Lambda functions to SQS interface endpoint"
}

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = var.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.sqs"
  private_dns_enabled = true
  subnet_ids          = [var.subnet_ids[0]]
  security_group_ids  = [var.function_security_group_id]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["sqs:SendMessage"]
      Resource  = aws_sqs_queue.reports.arn
    }]
  })
  depends_on = [aws_vpc_security_group_ingress_rule.sqs_self]
}

# reports.yml: BuilderRole (including its managed and inline policies)
resource "aws_iam_role" "builder" {
  name               = var.builder_role_name
  assume_role_policy = local.lambda_trust
}

resource "aws_iam_role_policy_attachment" "builder_vpc" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "builder" {
  name = "ReportBuilderAccess"
  role = aws_iam_role.builder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.reports.arn}/reports/*" },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.reports.arn }
    ]
  })
}

# reports.yml: BuilderLogGroup, BuilderFunction, QueueToBuilder
resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = 7
}

resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "Builds weekly meeting CSV reports and stores them in S3"
  package_type  = "Image"
  image_uri     = var.reports_image_uri
  architectures = ["x86_64"]
  role          = aws_iam_role.builder.arn
  memory_size   = 512
  timeout       = 60
  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.builder.name
  }
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.function_security_group_id]
  }
  environment {
    variables = {
      DATABASE_URL  = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${data.aws_cloudformation_stack.backend.outputs["DatabaseEndpoint"]}:5432/${var.db_name}"
      APP_TIMEZONE  = var.app_timezone
      LOG_LEVEL     = "INFO"
      REPORT_BUCKET = aws_s3_bucket.reports.id
    }
  }
  lifecycle {
    # TEMPORARY migration-only: verified equal in run-3ssTttqscv5f77r7;
    # only sensitivity metadata differs. Review removal after import with a plan.
    ignore_changes = [environment[0].variables["DATABASE_URL"]]
  }
  depends_on = [aws_iam_role_policy_attachment.builder_vpc, aws_iam_role_policy.builder]
}

resource "aws_lambda_event_source_mapping" "queue_to_builder" {
  event_source_arn = aws_sqs_queue.reports.arn
  function_name    = aws_lambda_function.builder.arn
  batch_size       = 1
  enabled          = true
  depends_on       = [aws_iam_role_policy.builder]
}

# reports.yml: SchedulerRole, WeeklyReportSchedule
resource "aws_iam_role" "scheduler" {
  name = var.scheduler_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["scheduler.amazonaws.com"] }
      Action    = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "SendWeeklyReportRequest"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.reports.arn }]
  })
}

resource "aws_scheduler_schedule" "weekly_report" {
  name                         = "${var.project_name}-weekly-report"
  group_name                   = "default"
  description                  = "Request the previous week's meeting report every Monday morning"
  schedule_expression          = "cron(0 8 ? * MON *)"
  schedule_expression_timezone = var.app_timezone
  state                        = "ENABLED"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_sqs_queue.reports.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = "{\"week\":null,\"source\":\"schedule\"}"
  }
  depends_on = [aws_iam_role_policy.scheduler]
}

# reports.yml: MailerRole, including its policies
resource "aws_iam_role" "mailer" {
  name               = var.mailer_role_name
  assume_role_policy = local.lambda_trust
}

resource "aws_iam_role_policy_attachment" "mailer_basic" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer" {
  name = "ReportMailerAccess"
  role = aws_iam_role.mailer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.reports.arn}/reports/*" },
      { Effect = "Allow", Action = ["ses:SendRawEmail"], Resource = "*" }
    ]
  })
}

# reports.yml: MailerLogGroup, MailerFunction, MailerInvokePermission, ReportEmailIdentity
resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = 7
}

resource "aws_lambda_function" "mailer" {
  function_name = "${var.project_name}-report-mailer"
  description   = "Emails generated weekly meeting CSV reports"
  package_type  = "Image"
  image_uri     = var.reports_image_uri
  architectures = ["x86_64"]
  role          = aws_iam_role.mailer.arn
  memory_size   = 256
  timeout       = 30
  image_config {
    command = ["app.reports.mailer_handler.handler"]
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.mailer.name
  }
  environment {
    variables = {
      LOG_LEVEL         = "INFO"
      REPORT_SENDER     = "reports@${aws_sesv2_email_identity.reports.email_identity}"
      REPORT_RECIPIENTS = var.report_recipients
    }
  }
  depends_on = [aws_iam_role_policy_attachment.mailer_basic, aws_iam_role_policy.mailer]
}

resource "aws_lambda_permission" "mailer" {
  statement_id   = var.mailer_permission_statement_id
  function_name  = aws_lambda_function.mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_account = var.aws_account_id
  source_arn     = aws_s3_bucket.reports.arn
}

resource "aws_sesv2_email_identity" "reports" {
  email_identity = var.report_domain
}
