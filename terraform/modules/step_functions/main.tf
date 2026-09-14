variable "bucket_name"                { type = string }
variable "role_arn"                   { type = string }
variable "bronze_to_silver_job_name"  { type = string }
variable "silver_to_gold_job_name"    { type = string }
variable "crawler_name"               { type = string }
variable "sns_topic_arn"              { type = string }
variable "region"                     { type = string }
variable "account_id"                 { type = string }

resource "aws_sfn_state_machine" "daily" {
  name     = "weather_daily_pipeline"
  role_arn = var.role_arn

  definition = templatefile("${path.module}/../../../stepfunctions/weather_daily_pipeline.json", {
    bucket_name              = var.bucket_name
    bronze_to_silver_job     = var.bronze_to_silver_job_name
    silver_to_gold_job       = var.silver_to_gold_job_name
    crawler_name             = var.crawler_name
    sns_topic_arn            = var.sns_topic_arn
  })
}

resource "aws_sfn_state_machine" "full_reload" {
  name     = "weather_full_reload_pipeline"
  role_arn = var.role_arn

  definition = templatefile("${path.module}/../../../stepfunctions/weather_full_reload_pipeline.json", {
    bucket_name              = var.bucket_name
    bronze_to_silver_job     = var.bronze_to_silver_job_name
    silver_to_gold_job       = var.silver_to_gold_job_name
    crawler_name             = var.crawler_name
    sns_topic_arn            = var.sns_topic_arn
  })
}

output "daily_state_machine_arn"       { value = aws_sfn_state_machine.daily.arn }
output "full_reload_state_machine_arn" { value = aws_sfn_state_machine.full_reload.arn }