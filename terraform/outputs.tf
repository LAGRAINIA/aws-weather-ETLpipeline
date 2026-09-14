output "bucket_name" {
  value = module.s3_datalake.bucket_name
}

output "lambda_function_name" {
  value = module.lambda_fetch_weather.function_name
}

output "daily_state_machine_arn" {
  value = module.step_functions.daily_state_machine_arn
}

output "full_reload_state_machine_arn" {
  value = module.step_functions.full_reload_state_machine_arn
}

output "athena_database_name" {
  value = module.glue_jobs.database_name
}