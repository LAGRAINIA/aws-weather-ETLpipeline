variable "bucket_name"     { type = string }
variable "secret_name"     { type = string }
variable "role_arn"        { type = string }
variable "lambda_zip_path" { type = string }
variable "layer_zip_path"  { type = string }

resource "aws_lambda_layer_version" "requests" {
  layer_name          = "requests-layer"
  filename            = var.layer_zip_path
  compatible_runtimes = ["python3.13"]
  source_code_hash    = filebase64sha256(var.layer_zip_path)
}

resource "aws_lambda_function" "fetch_weather" {
  function_name    = "fetch_weather_data"
  role             = var.role_arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  timeout          = 120
  memory_size      = 512
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  layers = [aws_lambda_layer_version.requests.arn]

  environment {
    variables = {
      S3_BUCKET   = var.bucket_name
      SECRET_NAME = var.secret_name
    }
  }
}

resource "aws_scheduler_schedule" "hourly_fetch" {
  name                = "weather-hourly-fetch"
  schedule_expression = "rate(1 hour)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.fetch_weather.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

resource "aws_iam_role" "scheduler" {
  name = "weather-scheduler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  role = aws_iam_role.scheduler.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.fetch_weather.arn
    }]
  })
}

output "function_name" { value = aws_lambda_function.fetch_weather.function_name }
output "function_arn"  { value = aws_lambda_function.fetch_weather.arn }