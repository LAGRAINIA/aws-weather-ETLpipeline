variable "project_name" { type = string }
variable "alert_email"  { type = string }

resource "aws_sns_topic" "alerts" {
  name = "weather-pipeline-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "weather-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 900
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    FunctionName = "fetch_weather_data"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }