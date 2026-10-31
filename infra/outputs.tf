# Public outputs used by application tooling after the Terraform migration.
output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "issuer" {
  value = "https://${aws_cognito_user_pool.main.endpoint}"
}

output "hosted_domain" {
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
}

output "google_enabled" {
  value = tostring(local.has_google)
}

output "report_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "report_queue_url" {
  value = aws_sqs_queue.reports.url
}

output "report_queue_name" {
  description = "Name of the existing weekly report SQS queue"
  value       = aws_sqs_queue.reports.name
}

output "report_queue_arn" {
  value = aws_sqs_queue.reports.arn
}

output "report_dead_letter_queue_url" {
  value = aws_sqs_queue.report_dlq.url
}

output "builder_function_name" {
  value = aws_lambda_function.builder.function_name
}

output "builder_log_group_name" {
  value = aws_cloudwatch_log_group.builder.name
}

output "weekly_report_schedule_name" {
  value = aws_scheduler_schedule.weekly_report.name
}

output "report_domain" {
  value = aws_sesv2_email_identity.reports.email_identity
}

# SES exposes DKIM tokens as a set; sorting makes numbered outputs stable.
# DNS record ordering is immaterial: all three name/value pairs are returned.
output "dkim_name_1" {
  value = "${sort(tolist(aws_sesv2_email_identity.reports.dkim_signing_attributes[0].tokens))[0]}._domainkey.${aws_sesv2_email_identity.reports.email_identity}"
}

output "dkim_value_1" {
  value = "${sort(tolist(aws_sesv2_email_identity.reports.dkim_signing_attributes[0].tokens))[0]}.dkim.amazonses.com"
}

output "dkim_name_2" {
  value = "${sort(tolist(aws_sesv2_email_identity.reports.dkim_signing_attributes[0].tokens))[1]}._domainkey.${aws_sesv2_email_identity.reports.email_identity}"
}

output "dkim_value_2" {
  value = "${sort(tolist(aws_sesv2_email_identity.reports.dkim_signing_attributes[0].tokens))[1]}.dkim.amazonses.com"
}

output "dkim_name_3" {
  value = "${sort(tolist(aws_sesv2_email_identity.reports.dkim_signing_attributes[0].tokens))[2]}._domainkey.${aws_sesv2_email_identity.reports.email_identity}"
}

output "dkim_value_3" {
  value = "${sort(tolist(aws_sesv2_email_identity.reports.dkim_signing_attributes[0].tokens))[2]}.dkim.amazonses.com"
}

output "mailer_function_name" {
  value = aws_lambda_function.mailer.function_name
}

output "mailer_log_group_name" {
  value = aws_cloudwatch_log_group.mailer.name
}

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}

output "parser_function_url" {
  value = aws_lambda_function_url.parser.function_url
}

output "parser_log_group_name" {
  value = aws_cloudwatch_log_group.parser.name
}

output "parser_role_arn" {
  value = aws_iam_role.parser.arn
}
