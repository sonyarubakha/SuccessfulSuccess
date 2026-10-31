# auth.yml: UserPool. Keep immutable sign-in/schema settings unchanged at adoption.
resource "aws_cognito_user_pool" "main" {
  name                     = "${var.project_name}-users"
  user_pool_tier           = "ESSENTIALS"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  username_configuration {
    case_sensitive = false
  }
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    # Verified against the existing pool with describe-user-pool on 2026-10-31.
    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  lifecycle {
    prevent_destroy = true
  }
}

# auth.yml: UserPoolDomain
resource "aws_cognito_user_pool_domain" "main" {
  user_pool_id          = aws_cognito_user_pool.main.id
  domain                = "${var.project_name}-${var.aws_account_id}"
  managed_login_version = 2
}

# auth.yml: GoogleIdentityProvider (HasGoogle)
resource "aws_cognito_identity_provider" "google" {
  count         = local.has_google ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"
  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }
  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    username       = "sub"
  }
  lifecycle {
    # Cognito populates these discovery fields; keep client ID and scopes managed.
    ignore_changes = [
      provider_details["attributes_url"],
      provider_details["attributes_url_add_attributes"],
      provider_details["authorize_url"],
      provider_details["oidc_issuer"],
      provider_details["token_request_method"],
      provider_details["token_url"],
      # TEMPORARY migration-only: verified equal in run-3ssTttqscv5f77r7;
      # only sensitivity metadata differs. Review removal after import with a plan.
      provider_details["client_secret"],
    ]
  }
}

# auth.yml: UserPoolClient
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id
  # generate_secret is creation-only and is not populated by Cognito on import.
  # Omit it to preserve the existing public client without forcing replacement.
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  access_token_validity         = 1
  id_token_validity             = 1
  refresh_token_validity        = 30
  # Existing token units use Cognito defaults (hours/hours/days), imported as null.
  supported_identity_providers         = concat(["COGNITO"], aws_cognito_identity_provider.google[*].provider_name)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.app_urls
  logout_urls                          = var.app_urls
  lifecycle {
    prevent_destroy = true
  }
}

# auth.yml: ManagedLoginBranding
resource "aws_cognito_managed_login_branding" "web" {
  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.web.id
  use_cognito_provided_values = true
  depends_on                  = [aws_cognito_user_pool_domain.main]
  lifecycle {
    prevent_destroy = true
  }
}
