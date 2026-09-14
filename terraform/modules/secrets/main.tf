variable "api_key_secret_name" { type = string }

resource "aws_secretsmanager_secret" "api_key" {
  name = var.api_key_secret_name
}

# NOTE: don't put the actual key in Terraform.
# Populate it manually once with:
#   aws secretsmanager put-secret-value --secret-id openweathermap/api_key \
#     --secret-string '{"api_key":"YOUR_KEY"}'

output "secret_name" { value = aws_secretsmanager_secret.api_key.name }
output "secret_arn"  { value = aws_secretsmanager_secret.api_key.arn }