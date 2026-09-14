# AWS Weather Data Pipeline

A production-style serverless ETL pipeline on AWS that ingests weather data from a public API, transforms it through a medallion architecture (Bronze → Silver → Gold), and exposes it for analytics.

## Architecture

![Architecture](docs/architecture.png)

## Tech Stack

**Compute & Orchestration**
- AWS Lambda — event-driven ingestion
- AWS Glue Spark Jobs — distributed transformations
- AWS Step Functions — pipeline orchestration
- Amazon EventBridge — scheduled triggers

**Storage & Catalog**
- Amazon S3 — data lake (Bronze/Silver/Gold layers)
- AWS Glue Data Catalog — metadata
- AWS Glue Crawlers — schema discovery

**Query & Consumption**
- Amazon Athena — SQL over S3

**Security & Observability**
- AWS Secrets Manager — API key storage
- Amazon CloudWatch — logs, metrics, dashboards
- Amazon SNS — alerting
- AWS IAM — dedicated role per service

## Key Features

- **Event-driven ingestion** — Lambda pulls 20 European cities every hour from OpenWeatherMap
- **Medallion architecture** — Bronze (raw JSON) → Silver (typed & deduped Parquet) → Gold (business marts)
- **Idempotent incremental writes** — dynamic partition overwrite preserves history on reruns
- **Full-reload support** — same jobs handle both daily incremental (`--processing_date=2026-09-14`) and full backfill (`--processing_date=all`)
- **Automatic alerting** — SNS notifications on success and failure
- **Dual pipelines** — daily incremental + on-demand full reload, sharing the same underlying jobs

## Project Structure

`​``
src/
├── lambda/       # ingestion Lambda
└── glue/         # transformation Spark scripts
stepfunctions/    # orchestration state machines
athena/           # DDL and analytical queries
terraform/        # infrastructure as code
`​``

## Quick Start

### Prerequisites

- AWS CLI configured with sufficient permissions
- Terraform >= 1.5
- Python 3.11+
- An OpenWeatherMap API key (free at https://openweathermap.org/api)

### Deploy

`​``bash
# 1. Store your API key in Secrets Manager
aws secretsmanager create-secret \
    --name openweathermap/api_key \
    --secret-string '{"api_key":"YOUR_KEY"}'

# 2. Deploy infrastructure with Terraform
cd terraform
terraform init
terraform apply

# 3. Upload Glue scripts and Lambda code
cd ..
./scripts/deploy_glue_scripts.sh
./scripts/deploy_lambda.sh
`​``

### Test

`​``bash
# Trigger the daily pipeline manually
aws stepfunctions start-execution \
    --state-machine-arn $(terraform -chdir=terraform output -raw daily_state_machine_arn) \
    --input '{}'

# Query the results
aws athena start-query-execution \
    --query-string "SELECT date, COUNT(*) FROM weather_analytics.city_daily_stats GROUP BY date"
`​``

## Data Quality

Each Glue job includes:
- Physical plausibility filters (temperature -50 to 60°C, humidity 0-100%)
- Deduplication by `city + hour` keeping the latest ingestion
- Null-safety on critical columns

## Cost

Running the full pipeline (hourly Lambda + daily Glue + queries) costs less than **$5/month** at current AWS pricing.

## Screenshots

### CloudWatch Dashboard
![Dashboard](docs/screenshots/cloudwatch-dashboard.png)

### Step Functions Execution
![Success](docs/screenshots/step-functions-success.png)

### Athena Query
![Athena](docs/screenshots/athena-query.png)

## Author

**Anass Lagraini** — Data Engineer
[LinkedIn](https://linkedin.com/in/anass-lagraini) | [Email](mailto:anass.lagraini94@gmail.com)

## License

MIT