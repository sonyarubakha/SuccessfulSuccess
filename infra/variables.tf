variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "backend_stack_name" {
  type = string
}

variable "app_urls" {
  type = list(string)
}

variable "google_client_id" {
  type = string
}

variable "google_client_secret" {
  description = "Set only via TF_VAR_google_client_secret or a sensitive HCP Terraform variable; also stored in state."
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet is required; preserve the original order for the SQS endpoint."
  }
}

variable "route_table_ids" {
  type = list(string)
}

variable "function_security_group_id" {
  type = string
}

variable "reports_image_uri" {
  type = string
}

variable "ai_image_uri" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  description = "Existing database password, supplied outside repository files; also stored in Lambda environment/state."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{8,41}$", var.db_password))
    error_message = "Match the existing CloudFormation password constraint (8–41 letters, digits, underscores or hyphens)."
  }
}

variable "app_timezone" {
  type = string
}

variable "report_domain" {
  type = string
}

variable "report_recipients" {
  type = string
}

variable "builder_role_name" {
  type = string
}

variable "scheduler_role_name" {
  type = string
}

variable "mailer_role_name" {
  type = string
}

variable "parser_role_name" {
  type = string
}

variable "mailer_permission_statement_id" {
  type = string
}

variable "parser_url_permission_statement_id" {
  type = string
}

variable "parser_invoke_permission_statement_id" {
  type = string
}

variable "parser_model" {
  type = string
}

variable "parser_input_price" {
  type = number
}

variable "parser_output_price" {
  type = number
}

variable "cors_origins" {
  type = list(string)
}

variable "budget_email" {
  description = "Empty disables the budget, matching HasBudgetEmail in ai.yml."
  type        = string
}
