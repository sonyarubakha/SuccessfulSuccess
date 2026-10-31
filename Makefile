COMPOSE ?= docker compose

# Windows: the recipes are POSIX shell, and native GNU make (winget install
# ezwinports.make) would hand them to cmd.exe. Run them with the bash, sed, awk,
# curl and friends that Git for Windows ships instead, whichever terminal make is
# started from. Installed Git elsewhere? make GIT_HOME="D:/Tools/Git" ...
# MSYS2/Cygwin make already has a POSIX shell, so it is left alone.
ifeq ($(OS),Windows_NT)
ifeq ($(findstring msys,$(MAKE_HOST))$(findstring cygwin,$(MAKE_HOST)),)
GIT_HOME ?= C:/Program Files/Git
export PATH := $(GIT_HOME)/bin;$(GIT_HOME)/usr/bin;$(PATH)
SHELL := bash.exe
.SHELLFLAGS := -c
endif
endif

# Local configuration (gitignored). These assignments beat variables exported in
# the shell, so override one on the command line instead: make aws-deploy-backend
# ECS_CPU_ARCH=ARM64
-include .env
# Legacy CloudFormation stacks and Terraform providers use this deployment region.
AWS_REGION ?= us-east-1
PARSER_MODEL ?= amazon.nova-pro-v1:0
ifeq ($(strip $(PROJECT_NAME)),)
PROJECT_NAME := successfulsuccess
endif

ifeq ($(strip $(APP_TIMEZONE)),)
APP_TIMEZONE := Europe/Kyiv
endif
export AWS_REGION PROJECT_NAME
# On Windows, stop Git's bash rewriting container paths such as /aws or
# /dev/null into C:/Program Files/Git/... before docker sees them.
export MSYS_NO_PATHCONV := 1
export MSYS2_ARG_CONV_EXCL := *

# Use the locally configured AWS CLI for legacy stacks and application commands.
# Override AWS to use another CLI command or wrapper.
AWS ?= aws
TERRAFORM ?= terraform

# Read named public outputs from the HCP workspace configured in infra/versions.tf.
# Requires terraform login and a locally initialized cloud backend; never applies.
terraform-output = $(TERRAFORM) -chdir=infra output -raw $(1)
HCP_WORKSPACE_URL = https://app.terraform.io/app/successfulsuccess-lab7-org/workspaces/successfulsuccess-lab7

APP_STACK ?= $(PROJECT_NAME)-backend
SERVERLESS_STACK ?= $(PROJECT_NAME)-serverless-backend
ECR_STACK ?= $(PROJECT_NAME)-ecr
FRONTEND_STACK ?= $(PROJECT_NAME)-frontend
IMAGE_TAG ?= $(shell git rev-parse HEAD)

IMAGE_PLATFORM ?= linux/amd64
# Every stack carries this tag, and CloudFormation copies it onto each resource
# that supports tags, so Cost Explorer and Resource Groups can find the project.
STACK_TAGS = --tags "PROJECT_NAME=$(PROJECT_NAME)"

# infra/certificate.sh reuses the CLI configured above. CloudFront only reads
# certificates from us-east-1, so that is where the frontend's goes.
CERT = AWS_CLI="$(AWS)" AWS_CERT_REGION=us-east-1 infra/certificate.sh

# $(call stack-output,<stack>,<output key>)
stack-output = $(AWS) cloudformation describe-stacks --stack-name $(1) \
	--query 'Stacks[0].Outputs[?OutputKey==`$(2)`].OutputValue' --output text

# CloudFormation refuses to update a stack that is still busy.
# Wait for any *_IN_PROGRESS operation to settle instead of failing.
# $(call wait-stack-idle,<stack>)
wait-stack-idle = while status=$$($(AWS) cloudformation describe-stacks --stack-name $(1) \
		--query 'Stacks[0].StackStatus' --output text 2>/dev/null | tr -d '[:space:]'); \
		case "$$status" in \
			REVIEW_IN_PROGRESS|"") false ;; \
			*_IN_PROGRESS) true ;; \
			*) false ;; \
		esac; do \
		echo "$(1) is $$status — waiting for it to settle..."; sleep 30; done

# A stack whose first create failed sits in ROLLBACK_COMPLETE, which
# CloudFormation can only delete. It holds no resources, so clear it and let the
# deploy start over.
# $(call clear-failed-create,<stack>)
clear-failed-create = status=$$($(AWS) cloudformation describe-stacks --stack-name $(1) \
		--query 'Stacks[0].StackStatus' --output text 2>/dev/null | tr -d '[:space:]'); \
		case "$$status" in \
			ROLLBACK_COMPLETE|REVIEW_IN_PROGRESS) \
				echo "$(1) is $$status — deleting it before retrying"; \
				$(AWS) cloudformation delete-stack --stack-name $(1) && \
				$(AWS) cloudformation wait stack-delete-complete --stack-name $(1) ;; \
		esac

# Fail early when the configured AWS CLI cannot authenticate.
define require-aws-credentials
        @$(AWS) sts get-caller-identity >/dev/null || { \
                echo "AWS CLI credentials are not configured — run: aws configure"; \
                exit 1; }
endef

define require-db-password
	@test -n "$(AWS_DB_PASSWORD)" || { \
		echo "AWS_DB_PASSWORD is empty — set it in .env (8+ chars, [A-Za-z0-9_-] only)"; \
		exit 1; }
endef

.PHONY: help up up-build down down-v logs ps migrate revision seed test lint fmt shell-backend psql \
        aws-whoami llm-hello parse aws-deploy aws-deploy-auth aws-auth-env aws-ecr aws-push aws-deploy-backend aws-deploy-reports report-now aws-migrate aws-url aws-status aws-logs \
        aws-frontend-cert aws-deploy-frontend aws-frontend-url aws-destroy \
        aws-deploy-ai aws-release-backend infra-ready infra-workflow deploy-backend deploy-frontend
help:
	@grep -hE '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack
	$(COMPOSE) up

up-build: ## Rebuild images and start the whole stack
	$(COMPOSE) up --build

down: ## Stop the stack
	$(COMPOSE) down

down-v: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

logs: ## Follow logs from every service
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply database migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add column"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

seed: ## Insert demo meetings for today for one user: make seed owner=<cognito-sub>
	@test -n "$(owner)" || { echo "Usage: make seed owner=<cognito-sub> (the user's sub from the Cognito console)"; exit 1; }
	$(COMPOSE) exec backend python -m app.seed "$(owner)"

test: ## Run the backend test suite against a throwaway database
	$(COMPOSE) exec db psql -U app -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='meetings_test'" | grep -q 1 || \
		$(COMPOSE) exec db createdb -U app meetings_test
	$(COMPOSE) exec -e DATABASE_URL=postgresql+asyncpg://app:app@db:5432/meetings_test backend pytest -q

lint: ## Lint backend and frontend
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend npm run lint

fmt: ## Format the backend code
	$(COMPOSE) exec backend ruff format .

shell-backend: ## Open a shell in the backend container
	$(COMPOSE) exec backend sh

psql: ## Open psql against the application database
	$(COMPOSE) exec db psql -U app -d meetings

aws-whoami: ## Verify the AWS credentials in .env
	$(require-aws-credentials)
	$(AWS) sts get-caller-identity

llm-hello: ## Call Amazon Nova through Amazon Bedrock and print usage
	@cd backend && AWS_REGION="$(AWS_REGION)" PARSER_MODEL="$(PARSER_MODEL)" \
		uv run python -m app.ai.hello

parse: ## Parse pasted agenda text: make parse TEXT="..."
	@test -n "$(TEXT)" || { echo 'Usage: make parse TEXT="agenda text"'; exit 1; }
	@cd backend && AWS_REGION="$(AWS_REGION)" PARSER_MODEL="$(PARSER_MODEL)" \
		uv run python -m app.ai.parse_cli "$(TEXT)"

infra-workflow: ## Show the VCS-driven Terraform workflow and workspace
	@echo "Edit infra/, review and push to GitHub branch lab7 when authorized."
	@echo "Review the remote plan and approve manually in $(HCP_WORKSPACE_URL)"
	@echo "Auto-apply is disabled; Terraform-managed infrastructure is not applied by Make."

infra-ready: ## Check access to the existing public HCP Terraform outputs (read-only)
	@set -e; \
		for output in user_pool_id user_pool_client_id issuer hosted_domain google_enabled parser_function_url report_queue_url; do \
			value=$$($(call terraform-output,$$output)) || { \
				echo "Cannot read HCP output $$output; see README HCP authentication and initialization."; exit 1; }; \
			test -n "$$value" || { echo "HCP output $$output is empty"; exit 1; }; \
		done

aws-deploy: infra-ready ## Deploy the legacy CloudFormation backend and frontend using existing Terraform outputs
	@$(MAKE) --no-print-directory aws-deploy-backend
	@$(MAKE) --no-print-directory aws-deploy-frontend

aws-deploy-auth aws-deploy-reports aws-deploy-ai: ## Retired: manage Auth, Reports and AI through the HCP VCS workflow
	@echo "This infrastructure is owned by Terraform. Do not recreate its CloudFormation stacks."
	@echo "Use the reviewed GitHub lab7 workflow: $(HCP_WORKSPACE_URL)"
	@exit 1

aws-auth-env: ## Print public Cognito settings from HCP state for local .env
	@set -e; \
		pool=$$($(call terraform-output,user_pool_id)); \
		client=$$($(call terraform-output,user_pool_client_id)); \
		domain=$$($(call terraform-output,hosted_domain)); \
		google=$$($(call terraform-output,google_enabled)); \
		printf 'COGNITO_USER_POOL_ID=%s\nCOGNITO_CLIENT_ID=%s\nCOGNITO_DOMAIN=%s\nCOGNITO_GOOGLE_ENABLED=%s\n' "$$pool" "$$client" "$$domain" "$$google"

aws-ecr: ## Create the ECR repository for the backend image
	$(require-aws-credentials)
	$(AWS) cloudformation deploy \
		--stack-name $(ECR_STACK) \
		--template-file infra/ecr.yml \
		--no-fail-on-empty-changeset \
		$(STACK_TAGS) \
		--parameter-overrides "ProjectName=$(PROJECT_NAME)"

aws-push: ## Build the backend Lambda image and push it to ECR
	$(require-aws-credentials)
	@repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		echo "Pushing Lambda image $$repo:$(IMAGE_TAG) ($(IMAGE_PLATFORM))"; \
		$(AWS) ecr get-login-password | docker login --username AWS --password-stdin "$${repo%%/*}"; \
		docker buildx build \
			--platform $(IMAGE_PLATFORM) \
			--provenance=false \
			-f backend/Dockerfile.lambda \
			-t "$$repo:$(IMAGE_TAG)" \
			--push \
			./backend

aws-deploy-backend: infra-ready aws-ecr aws-push ## Deploy Lambda + Aurora and keep the compatibility CloudFront URL
	$(require-aws-credentials)
	$(require-db-password)
	@set -e; \
		pool=$$($(call terraform-output,user_pool_id)); \
		client=$$($(call terraform-output,user_pool_client_id)); \
		issuer=$$($(call terraform-output,issuer)); \
		case "$$pool" in ""|None) echo "No user pool output found — check the HCP Terraform workspace"; exit 1 ;; esac; \
		jwks=$$(curl -fsS "$$issuer/.well-known/jwks.json" | base64 | tr -d '\n'); \
		test -n "$$jwks" || { echo "Could not download Cognito JWKS"; exit 1; }; \
		vpc=$$($(AWS) ec2 describe-vpcs \
			--filters Name=isDefault,Values=true \
			--query 'Vpcs[0].VpcId' \
			--output text | tr -d '[:space:]'); \
		test "$$vpc" != "None" -a -n "$$vpc" || { echo "No default VPC"; exit 1; }; \
		subnets=$$($(AWS) ec2 describe-subnets \
			--filters Name=vpc-id,Values=$$vpc Name=default-for-az,Values=true \
			--query 'Subnets[].SubnetId' \
			--output text | tr '[:space:]' ',' | sed 's/,*$$//'); \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images \
			--repository-name "$${repo#*/}" \
			--image-ids imageTag=$(IMAGE_TAG) \
			--query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		cors="$(AWS_CORS_ORIGINS)"; \
		if [ -z "$$cors" ]; then \
			cors=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) 2>/dev/null | tr -d '[:space:]'); \
			case "$$cors" in ""|None) cors='*' ;; esac; \
		fi; \
		echo "Deploying serverless backend: $$repo@$$digest"; \
		$(call wait-stack-idle,$(SERVERLESS_STACK)); \
		$(call clear-failed-create,$(SERVERLESS_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(SERVERLESS_STACK) \
			--template-file infra/backend-serverless.yml \
			--capabilities CAPABILITY_IAM \
			--no-fail-on-empty-changeset \
			--tags "PROJECT_NAME=$(PROJECT_NAME)-serverless" \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)-serverless" \
				"VpcId=$$vpc" \
				"SubnetIds=$$subnets" \
				"ImageUri=$$repo@$$digest" \
				"Architecture=x86_64" \
				"DbPassword=$(AWS_DB_PASSWORD)" \
				"AppTimezone=$(APP_TIMEZONE)" \
				"CorsOrigins=$$cors" \
				"CognitoUserPoolId=$$pool" \
				"CognitoClientId=$$client" \
				"CognitoJwks=$$jwks" \
                            "ReportQueueName=$(PROJECT_NAME)-report-queue"; \
		origin=$$($(call stack-output,$(SERVERLESS_STACK),FunctionUrlDomain) | tr -d '[:space:]'); \
		$(AWS) cloudformation deploy \
			--stack-name $(APP_STACK) \
			--template-file infra/backend.yml \
			--no-fail-on-empty-changeset \
			--tags "PROJECT_NAME=$(PROJECT_NAME)" \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"ServerlessOriginDomain=$$origin"

	@$(MAKE) --no-print-directory aws-migrate
	@$(MAKE) --no-print-directory aws-url

report-now: ## Request an on-demand weekly report: make report-now WEEK=2026-W40
	$(require-aws-credentials)
	@test -n "$(WEEK)" || { echo "Usage: make report-now WEEK=YYYY-Www"; exit 1; }
	@set -e; \
		queue=$$($(call terraform-output,report_queue_url)); \
		test -n "$$queue" -a "$$queue" != "None" || { echo "Report queue output not found — check the HCP Terraform workspace"; exit 1; }; \
		$(AWS) sqs send-message \
			--queue-url "$$queue" \
			--message-body '{"week":"$(WEEK)","source":"manual"}'

aws-release-backend: aws-push ## Release new application code to the existing Lambda
	$(require-aws-credentials)
	@set -e; \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images \
			--repository-name "$${repo#*/}" \
			--image-ids imageTag=$(IMAGE_TAG) \
			--query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		fn=$$($(call stack-output,$(SERVERLESS_STACK),FunctionName) | tr -d '[:space:]'); \
		echo "Updating $$fn to $$repo@$$digest"; \
		$(AWS) lambda update-function-code \
			--function-name "$$fn" \
			--image-uri "$$repo@$$digest" \
			>/dev/null; \
		$(AWS) lambda wait function-updated \
			--function-name "$$fn"

	@$(MAKE) --no-print-directory aws-migrate

	@set -e; \
		api=$$($(call stack-output,$(APP_STACK),ApiUrl) | tr -d '[:space:]'); \
		echo "Checking $$api/health"; \
		curl -fsS "$$api/health"; \
		echo

aws-migrate: ## Apply Alembic migrations through Lambda
	@set -e; \
		fn=$$($(call stack-output,$(SERVERLESS_STACK),FunctionName) | tr -d '[:space:]'); \
		echo "Migrating database through $$fn"; \
		tmp=$$(mktemp); \
		err=$$($(AWS) lambda invoke \
			--function-name "$$fn" \
			--cli-binary-format raw-in-base64-out \
			--payload '{"action":"migrate"}' \
			--query FunctionError \
			--output text \
			"$$tmp" | tr -d '[:space:]'); \
		cat "$$tmp"; echo; \
		rm -f "$$tmp"; \
		test "$$err" = "None" || { echo "Migration failed: $$err"; exit 1; }

aws-url: ## Print the stable public backend URL
	@$(call stack-output,$(APP_STACK),ApiUrl)

aws-status: ## Show serverless backend state
	@$(AWS) cloudformation describe-stacks \
		--stack-name $(SERVERLESS_STACK) \
		--query 'Stacks[0].Outputs' \
		--output table
	@fn=$$($(call stack-output,$(SERVERLESS_STACK),FunctionName) | tr -d '[:space:]'); \
		$(AWS) lambda get-function-configuration \
			--function-name "$$fn" \
			--query '{state:State,lastUpdate:LastUpdateStatus,arch:Architectures[0],memory:MemorySize}' \
			--output table
	@echo "Public API:"
	@$(MAKE) --no-print-directory aws-url

aws-logs: ## Follow Lambda backend logs
	@log=$$($(call stack-output,$(SERVERLESS_STACK),LogGroupName) | tr -d '[:space:]'); \
		$(AWS) logs tail "$$log" --follow

aws-frontend-cert: ## Request and validate the HTTPS certificate for AWS_FRONTEND_DOMAIN (in us-east-1)
	$(require-aws-credentials)
	@test -n "$(AWS_FRONTEND_DOMAIN)" || { \
		echo "AWS_FRONTEND_DOMAIN is empty — set it in .env (e.g. app.example.com)"; exit 1; }
	@$(CERT) ensure "$(AWS_FRONTEND_DOMAIN)"

aws-deploy-frontend: infra-ready ## Deploy the frontend to S3 + CloudFront, built against the deployed backend URL
	$(require-aws-credentials)
	@api=$$($(call stack-output,$(APP_STACK),ApiUrl) 2>/dev/null | tr -d '[:space:]'); \
        case "$$api" in ""|None) \
                api="http://localhost:8000"; \
                echo "Backend is not deployed yet — building frontend with temporary API URL $$api"; \
        ;; esac; \
		domain=""; \
		if [ -n "$(AWS_FRONTEND_DOMAIN)" ]; then \
			cert=$$($(CERT) find "$(AWS_FRONTEND_DOMAIN)"); \
			test -n "$$cert" || { \
				echo "No issued us-east-1 certificate for $(AWS_FRONTEND_DOMAIN) — run: make aws-frontend-cert"; \
				exit 1; }; \
			zone=$$($(CERT) zone "$(AWS_FRONTEND_DOMAIN)"); \
			domain="DomainName=$(AWS_FRONTEND_DOMAIN) CertificateArn=$$cert HostedZoneId=$$zone"; \
			echo "custom domain: $(AWS_FRONTEND_DOMAIN) (Route 53 zone: $${zone:-none})"; \
		fi; \
		$(call wait-stack-idle,$(FRONTEND_STACK)); \
		$(call clear-failed-create,$(FRONTEND_STACK)); \
		echo "A new CloudFront distribution takes ~5 minutes to come up."; \
		$(AWS) cloudformation deploy \
			--stack-name $(FRONTEND_STACK) \
			--template-file infra/frontend.yml \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"PricingPlan=$(or $(AWS_CLOUDFRONT_PLAN),FREE)" \
				$$domain
	@echo "Cognito callback/logout URLs and parser CORS are managed through the HCP VCS workflow."
	@set -e; \
		api=$$($(call stack-output,$(APP_STACK),ApiUrl) 2>/dev/null | tr -d '[:space:]'); \
		case "$$api" in ""|None) api="http://localhost:8000" ;; esac; \
		pool=$$($(call terraform-output,user_pool_id)); \
		client=$$($(call terraform-output,user_pool_client_id)); \
		domain=$$($(call terraform-output,hosted_domain)); \
		google=$$($(call terraform-output,google_enabled)); \
		parser=$$($(call terraform-output,parser_function_url)); \
		test -n "$$parser" -a "$$parser" != "None" || { echo "AI parser URL not found"; exit 1; }; \
		bucket=$$($(call stack-output,$(FRONTEND_STACK),BucketName) | tr -d '[:space:]'); \
		dist=$$($(call stack-output,$(FRONTEND_STACK),DistributionId) | tr -d '[:space:]'); \
		echo "Building the static export against $$api"; \
		rm -rf frontend/out; \
		docker build --target export --output type=local,dest=frontend/out \
			--build-arg NEXT_PUBLIC_API_BASE_URL="$$api" \
			--build-arg NEXT_PUBLIC_AI_PARSER_URL="$$parser" \
			--build-arg NEXT_PUBLIC_COGNITO_USER_POOL_ID="$$pool" \
			--build-arg NEXT_PUBLIC_COGNITO_CLIENT_ID="$$client" \
			--build-arg NEXT_PUBLIC_COGNITO_DOMAIN="$$domain" \
			--build-arg NEXT_PUBLIC_COGNITO_GOOGLE_ENABLED="$$google" \
			./frontend || exit 1; \
		echo "Uploading to s3://$$bucket"; \
		$(AWS) s3 sync frontend/out "s3://$$bucket" --delete --exclude "*.html" \
			--cache-control "public,max-age=31536000,immutable" --only-show-errors || exit 1; \
		$(AWS) s3 sync frontend/out "s3://$$bucket" --delete --exclude "*" --include "*.html" \
			--cache-control "no-cache" --only-show-errors || exit 1; \
		$(AWS) cloudfront create-invalidation --distribution-id "$$dist" --paths "/*" \
			--query 'Invalidation.Status' --output text
	@$(MAKE) --no-print-directory aws-frontend-url
	@if [ -z "$(AWS_CORS_ORIGINS)" ]; then \
        allowed=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) | tr -d '[:space:]'); \
        echo "Frontend origin is $$allowed"; \
        echo "Run make deploy-backend again to update backend CORS to this origin."; \
	fi
	@if [ -n "$(AWS_FRONTEND_DOMAIN)" ] && [ -z "$$($(CERT) zone "$(AWS_FRONTEND_DOMAIN)")" ]; then \
		echo "Point $(AWS_FRONTEND_DOMAIN) at the distribution: CNAME $$($(call stack-output,$(FRONTEND_STACK),DistributionDomain) | tr -d '[:space:]')"; \
	fi

aws-frontend-url: ## Print the deployed site URL
	@$(call stack-output,$(FRONTEND_STACK),SiteUrl)

aws-destroy: ## Delete legacy frontend and compatibility API only; retain shared backend/ECR and Terraform resources
	$(require-aws-credentials)
	@printf 'Delete %s and %s? Frontend contents will be removed. Shared serverless backend, ECR and Terraform resources are retained. Type yes: ' \
		"$(FRONTEND_STACK)" "$(APP_STACK)"; \
		read answer; test "$$answer" = "yes" || { echo "Aborted."; exit 1; }
	@bucket=$$($(call stack-output,$(FRONTEND_STACK),BucketName) 2>/dev/null | tr -d '[:space:]'); \
		if [ -n "$$bucket" ] && [ "$$bucket" != "None" ]; then \
			echo "Emptying s3://$$bucket"; \
			$(AWS) s3 rm "s3://$$bucket" --recursive --only-show-errors || true; \
		fi
	-$(AWS) cloudformation delete-stack --stack-name $(FRONTEND_STACK)
	-$(AWS) cloudformation wait stack-delete-complete --stack-name $(FRONTEND_STACK)
	@echo "Deleting $(APP_STACK) — this may take several minutes."
	$(AWS) cloudformation delete-stack --stack-name $(APP_STACK)
	$(AWS) cloudformation wait stack-delete-complete --stack-name $(APP_STACK)
	@echo "Legacy frontend and compatibility API deleted. Shared serverless backend/ECR and Terraform resources remain."
	@echo "Full teardown requires a reviewed dependency-aware procedure; ECR images are still used by Terraform Lambdas."


deploy-backend: aws-deploy-backend ## Build, push and deploy the legacy CloudFormation Lambda backend

deploy-frontend: aws-deploy-frontend ## Build and deploy the frontend to S3 + CloudFront
