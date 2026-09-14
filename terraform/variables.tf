variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Base project name — used in resource naming"
  type        = string
  default     = "weather-datalake"
}

variable "alert_email" {
  description = "Email for SNS pipeline alerts"
  type        = string
}

variable "lambda_zip_path" {
  description = "Local path to the Lambda deployment package zip"
  type        = string
  default     = "../dist/fetch_weather_data.zip"
}

variable "layer_zip_path" {
  description = "Local path to the Lambda layer zip (requests library)"
  type        = string
  default     = "../dist/requests-layer.zip"
}