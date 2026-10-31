# Non-sensitive inputs for VCS-driven HCP Terraform runs.
# Keep private inputs in HCP Terraform workspace variables:
# db_password, google_client_secret, report_recipients, budget_email.
# Never add secrets or password-bearing connection strings to this file.

project_name                          = "successfulsuccess"
region                                = "us-east-1"
aws_account_id                        = "016355331754"
backend_stack_name                    = "successfulsuccess-serverless-backend"
app_urls                              = ["http://localhost:3000/", "https://d1gttz7ks3ajab.cloudfront.net/"]
google_client_id                      = "1036531336406-d138adgl1godou0atmr2hdsmfrt58ksq.apps.googleusercontent.com"
vpc_id                                = "vpc-02169524e2029c6b0"
subnet_ids                            = ["subnet-0c5651642aed1d2e9", "subnet-0560d755f7db8239b", "subnet-063d39313d8d66488", "subnet-04551ef949edbe235", "subnet-0639fa466d2474adf", "subnet-0ccea7527792de682"]
route_table_ids                       = ["rtb-060defce9e0ff70db"]
function_security_group_id            = "sg-0045f8a8c820b4837"
reports_image_uri                     = "016355331754.dkr.ecr.us-east-1.amazonaws.com/successfulsuccess-backend@sha256:890d188f774234f514d4d1f07d9dfdc136074c86aaa7408f207d46cb08a7f9a7"
ai_image_uri                          = "016355331754.dkr.ecr.us-east-1.amazonaws.com/successfulsuccess-backend@sha256:8f79539e7beb51d882bd02d1785cd530713d9895dd6f43649611b7da5e36b01e"
db_name                               = "meetings"
db_username                           = "app"
app_timezone                          = "Europe/Kyiv"
report_domain                         = "sslab5-7m3k9.dns.army"
builder_role_name                     = "successfulsuccess-reports-BuilderRole-ezq1MmJaOgXm"
scheduler_role_name                   = "successfulsuccess-reports-SchedulerRole-M25Bgwcw3gFl"
mailer_role_name                      = "successfulsuccess-reports-MailerRole-uOVi0AgNVKeN"
parser_role_name                      = "successfulsuccess-ai-ParserRole-9rby9FdnHT3M"
mailer_permission_statement_id        = "successfulsuccess-reports-MailerInvokePermission-UGcR8xyceN8U"
parser_url_permission_statement_id    = "successfulsuccess-ai-ParserUrlPermission-c1evi7Quxy2B"
parser_invoke_permission_statement_id = "successfulsuccess-ai-ParserInvokePermission-GFk1hHom80vP"
parser_model                          = "amazon.nova-pro-v1:0"
parser_input_price                    = 0.8
parser_output_price                   = 3.2
cors_origins                          = ["https://d1gttz7ks3ajab.cloudfront.net", "http://localhost:3000"]
