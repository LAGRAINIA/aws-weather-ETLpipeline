variable "bucket_name"       { type = string }
variable "role_arn"          { type = string }
variable "scripts_s3_prefix" { type = string }
variable "database_name"     { type = string }

resource "aws_glue_catalog_database" "weather" {
  name = var.database_name
}

resource "aws_glue_job" "bronze_to_silver" {
  name         = "weather_bronze_to_silver"
  role_arn     = var.role_arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2
  timeout      = 20

  command {
    name            = "glueetl"
    script_location = "s3://${var.bucket_name}/${var.scripts_s3_prefix}/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--bucket"                          = var.bucket_name
    "--processing_date"                 = "2026-01-01"    # default; overridden at runtime
    "--enable-metrics"                  = "true"
    "--enable-continuous-cloudwatch-log" = "true"
  }
}

resource "aws_glue_job" "silver_to_gold" {
  name         = "weather_silver_to_gold"
  role_arn     = var.role_arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2
  timeout      = 20

  command {
    name            = "glueetl"
    script_location = "s3://${var.bucket_name}/${var.scripts_s3_prefix}/silver_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--bucket"          = var.bucket_name
    "--processing_date" = "2026-01-01"
    "--enable-metrics"  = "true"
  }
}

resource "aws_glue_crawler" "gold" {
  name          = "weather_gold_crawler"
  role          = var.role_arn
  database_name = aws_glue_catalog_database.weather.name

  s3_target { path = "s3://${var.bucket_name}/gold/city_daily_stats/" }
  s3_target { path = "s3://${var.bucket_name}/gold/weather_alerts_summary/" }
  s3_target { path = "s3://${var.bucket_name}/gold/temperature_trends_weekly/" }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

output "bronze_to_silver_job_name" { value = aws_glue_job.bronze_to_silver.name }
output "silver_to_gold_job_name"   { value = aws_glue_job.silver_to_gold.name }
output "crawler_name"              { value = aws_glue_crawler.gold.name }
output "database_name"             { value = aws_glue_catalog_database.weather.name }