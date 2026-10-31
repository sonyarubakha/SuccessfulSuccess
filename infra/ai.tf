# ai.yml: MonthlyBudget (HasBudgetEmail)
resource "aws_budgets_budget" "ai_monthly" {
  count        = var.budget_email != "" ? 1 : 0
  account_id   = var.aws_account_id
  name         = "${var.project_name}-ai-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = "5"
  limit_unit   = "USD"
  cost_filter {
    name   = "Service"
    values = ["Amazon Bedrock"]
  }
  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }
}

# ai.yml: ParserRole, including its policies
resource "aws_iam_role" "parser" {
  name               = var.parser_role_name
  assume_role_policy = local.lambda_trust
}

resource "aws_iam_role_policy_attachment" "parser_basic" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser" {
  name = "InvokeAgendaModel"
  role = aws_iam_role.parser.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.region}::foundation-model/${var.parser_model}"
    }]
  })
}

# ai.yml: ParserLogGroup, ParserFunction
resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 7
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Parse meeting agendas using Amazon Nova on Bedrock"
  package_type  = "Image"
  image_uri     = var.ai_image_uri
  architectures = ["x86_64"]
  role          = aws_iam_role.parser.arn
  memory_size   = 512
  timeout       = 30
  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }
  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      PARSER_INPUT_PRICE   = tostring(var.parser_input_price)
      PARSER_OUTPUT_PRICE  = tostring(var.parser_output_price)
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      LOG_LEVEL            = "INFO"
    }
  }
  depends_on = [aws_iam_role_policy_attachment.parser_basic, aws_iam_role_policy.parser]
}

# ai.yml: ParserFunctionUrl, ParserUrlPermission, ParserInvokePermission
resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"
  cors {
    allow_origins = var.cors_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}

resource "aws_lambda_permission" "parser_url" {
  statement_id           = var.parser_url_permission_statement_id
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = aws_lambda_function_url.parser.authorization_type
}

resource "aws_lambda_permission" "parser_invoke" {
  statement_id             = var.parser_invoke_permission_statement_id
  function_name            = aws_lambda_function.parser.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}
