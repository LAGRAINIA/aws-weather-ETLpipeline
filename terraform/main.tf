terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket  = "weather-tf-state-anass"
    key     = "weather-pipeline/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "weather-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Get current account ID for use in ARNs
data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = var.project_name
}

module "s3_datalake" {
  source      = "./modules/s3_datalake"
  bucket_name = local.bucket_name
}

module "secrets" {
  source              = "./modules/secrets"
  api_key_secret_name = "openweathermap/api_key"
}

module "iam_roles" {
  source        = "./modules/iam_roles"
  bucket_arn    = module.s3_datalake.bucket_arn
  secret_arn    = module.secrets.secret_arn
  sns_topic_arn = module.observability.sns_topic_arn
}

module "observability" {
  source       = "./modules/observability"
  project_name = var.project_name
  alert_email  = var.alert_email
}

module "lambda_fetch_weather" {
  source          = "./modules/lambda_fetch_weather"
  bucket_name     = local.bucket_name
  secret_name     = module.secrets.secret_name
  role_arn        = module.iam_roles.lambda_role_arn
  lambda_zip_path = var.lambda_zip_path
  layer_zip_path  = var.layer_zip_path
}

module "glue_jobs" {
  source            = "./modules/glue_jobs"
  bucket_name       = local.bucket_name
  role_arn          = module.iam_roles.glue_role_arn
  scripts_s3_prefix = "scripts"
  database_name     = "weather_analytics"
}

module "step_functions" {
  source                    = "./modules/step_functions"
  bucket_name               = local.bucket_name
  role_arn                  = module.iam_roles.stepfunctions_role_arn
  bronze_to_silver_job_name = module.glue_jobs.bronze_to_silver_job_name
  silver_to_gold_job_name   = module.glue_jobs.silver_to_gold_job_name
  crawler_name              = module.glue_jobs.crawler_name
  sns_topic_arn             = module.observability.sns_topic_arn
  region                    = var.region
  account_id                = local.account_id
}