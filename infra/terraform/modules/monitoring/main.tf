locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# --- Alert topic, encrypted --------------------------------------------------------
# A customer managed key rather than alias/aws/sns: the AWS managed key's policy
# can't be changed to let CloudWatch use it, so alarms would fail to publish to
# the topic without any visible error.

data "aws_iam_policy_document" "alerts_key" {
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsPublish"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description         = "${local.name_prefix} SNS alerts topic"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.alerts_key.json
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- ECS -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${local.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Sustained high CPU - autoscaling should be kicking in; alerts if it's maxed out anyway"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${local.name_prefix}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
}

# --- ALB -------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 upstream 5xx responses in a minute, twice in a row"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "At least one task is failing its ALB health check"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p90"
  threshold           = 2 # seconds
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# --- RDS ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2 GiB, in bytes
  alarm_description   = "Less than 2GB free on the RDS volume"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}

# --- Application metrics from structured logs --------------------------------------
# The Django app logs one JSON `request` event per request (see
# app/conduit/apps/core/observability.py). Metric filters turn those lines into
# metrics without any agent or SDK in the container.

locals {
  app_namespace = "Conduit/App"
  request_event = "$.logger = \"conduit.request\""
}

resource "aws_cloudwatch_log_metric_filter" "requests" {
  name           = "${local.name_prefix}-requests"
  log_group_name = var.app_log_group_name
  pattern        = "{ ${local.request_event} }"

  metric_transformation {
    name          = "Requests"
    namespace     = local.app_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "server_errors" {
  name           = "${local.name_prefix}-5xx"
  log_group_name = var.app_log_group_name
  pattern        = "{ ${local.request_event} && $.status >= 500 }"

  metric_transformation {
    name          = "Http5xx"
    namespace     = local.app_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "request_duration" {
  name           = "${local.name_prefix}-request-duration"
  log_group_name = var.app_log_group_name
  pattern        = "{ ${local.request_event} }"

  metric_transformation {
    name      = "RequestDuration"
    namespace = local.app_namespace
    value     = "$.duration_ms"
    unit      = "Milliseconds"
  }
}

resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  name           = "${local.name_prefix}-error-logs"
  log_group_name = var.app_log_group_name
  pattern        = "{ $.level = \"ERROR\" || $.level = \"CRITICAL\" }"

  metric_transformation {
    name          = "ErrorLogs"
    namespace     = local.app_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_error_logs" {
  alarm_name          = "${local.name_prefix}-app-error-logs"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorLogs"
  namespace           = local.app_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Django logged 5+ ERROR lines in 5 minutes - start from the 'errors' Logs Insights query"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# --- Availability SLO: 99% of requests answered without a 5xx ----------------------
# Measured at the ALB so it also counts requests that never reached a task
# (ELB 5xx: no healthy targets, timeouts). Pages when the 5xx ratio burns
# through the 1% error budget for 15 minutes straight.

resource "aws_cloudwatch_metric_alarm" "availability_slo" {
  alarm_name          = "${local.name_prefix}-availability-slo"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 1
  alarm_description   = "More than 1% of requests returned 5xx for 15 minutes (SLO: 99% availability)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "IF(requests > 0, 100 * (target_5xx + elb_5xx) / requests, 0)"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "target_5xx"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "elb_5xx"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }
}

# --- Saved Logs Insights queries -----------------------------------------------------

resource "aws_cloudwatch_query_definition" "errors" {
  name            = "${local.name_prefix}/errors"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, level, logger, message, request_id, exception
    | filter level in ["ERROR", "CRITICAL"]
    | sort @timestamp desc
    | limit 100
  EOT
}

resource "aws_cloudwatch_query_definition" "slowest_routes" {
  name            = "${local.name_prefix}/slowest-routes"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    filter logger = "conduit.request"
    | stats count(*) as requests, avg(duration_ms) as avg_ms, pct(duration_ms, 95) as p95_ms, pct(duration_ms, 99) as p99_ms by method, route
    | sort p95_ms desc
  EOT
}

resource "aws_cloudwatch_query_definition" "status_by_route" {
  name            = "${local.name_prefix}/status-by-route"
  log_group_names = [var.app_log_group_name]
  query_string    = <<-EOT
    filter logger = "conduit.request" and status >= 400
    | stats count(*) as responses by status, method, route
    | sort responses desc
  EOT
}

resource "aws_cloudwatch_query_definition" "trace_request" {
  name            = "${local.name_prefix}/trace-request"
  log_group_names = [var.app_log_group_name]
  # Paste the X-Request-Id response header (or ALB trace id) in place of REQUEST_ID.
  query_string = <<-EOT
    fields @timestamp, level, logger, message, status, duration_ms, exception
    | filter request_id = "REQUEST_ID"
    | sort @timestamp asc
  EOT
}

resource "aws_cloudwatch_query_definition" "slow_queries" {
  name            = "${local.name_prefix}/postgres-slow-queries"
  log_group_names = [var.db_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, @message
    | filter @message like /duration:/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "rejected_flows" {
  name            = "${local.name_prefix}/vpc-rejected-flows"
  log_group_names = [var.flow_logs_log_group_name]
  query_string    = <<-EOT
    parse @message "* * * * * * * * * * * * * *" as version, account, eni, src, dst, srcport, dstport, protocol, packets, bytes, start, end, action, status
    | filter action = "REJECT"
    | stats count(*) as attempts by src, dstport
    | sort attempts desc
    | limit 50
  EOT
}

# --- Dashboard -----------------------------------------------------------------------

locals {
  region = data.aws_region.current.name

  widgets = [
    {
      title = "App requests / 5xx (from logs)"
      metrics = [
        [local.app_namespace, "Requests", { stat = "Sum" }],
        [local.app_namespace, "Http5xx", { stat = "Sum" }],
        [local.app_namespace, "ErrorLogs", { stat = "Sum" }],
      ]
    },
    {
      title = "App latency p50 / p95 / p99 (ms)"
      metrics = [
        [local.app_namespace, "RequestDuration", { stat = "p50" }],
        [local.app_namespace, "RequestDuration", { stat = "p95" }],
        [local.app_namespace, "RequestDuration", { stat = "p99" }],
      ]
    },
    {
      title = "ECS CPU / Memory"
      metrics = [
        ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
        ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
      ]
    },
    {
      title = "ALB requests / 5xx / latency"
      metrics = [
        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
        ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
        ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
        ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p90", yAxis = "right" }],
      ]
    },
    {
      title = "RDS CPU / connections / free storage"
      metrics = [
        ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id],
        ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id],
        ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id, { yAxis = "right" }],
      ]
    },
    {
      title = "WAF allowed / blocked"
      metrics = [
        ["AWS/WAFV2", "AllowedRequests", "WebACL", var.waf_web_acl_name, "Region", local.region, "Rule", "ALL", { stat = "Sum" }],
        ["AWS/WAFV2", "BlockedRequests", "WebACL", var.waf_web_acl_name, "Region", local.region, "Rule", "ALL", { stat = "Sum" }],
      ]
    },
    {
      title = "CloudFront requests / error rates"
      # CloudFront publishes its metrics in us-east-1 only, under Region=Global.
      region = "us-east-1"
      metrics = [
        ["AWS/CloudFront", "Requests", "DistributionId", var.cloudfront_distribution_id, "Region", "Global", { stat = "Sum" }],
        ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global", { yAxis = "right" }],
        ["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global", { yAxis = "right" }],
      ]
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.name_prefix

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "alarm"
          x      = 0
          y      = 0
          width  = 24
          height = 3
          properties = {
            title = "Alarms"
            alarms = [
              aws_cloudwatch_metric_alarm.availability_slo.arn,
              aws_cloudwatch_metric_alarm.app_error_logs.arn,
              aws_cloudwatch_metric_alarm.alb_5xx.arn,
              aws_cloudwatch_metric_alarm.alb_latency.arn,
              aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.arn,
              aws_cloudwatch_metric_alarm.ecs_cpu_high.arn,
              aws_cloudwatch_metric_alarm.ecs_memory_high.arn,
              aws_cloudwatch_metric_alarm.rds_cpu_high.arn,
              aws_cloudwatch_metric_alarm.rds_storage_low.arn,
            ]
          }
        },
      ],
      [
        for i, w in local.widgets : {
          type   = "metric"
          x      = (i % 2) * 12
          y      = 3 + floor(i / 2) * 6
          width  = 12
          height = 6
          properties = {
            title   = w.title
            view    = "timeSeries"
            region  = lookup(w, "region", local.region)
            period  = 60
            metrics = w.metrics
          }
        }
      ],
      [
        {
          type   = "log"
          x      = 0
          y      = 3 + ceil(length(local.widgets) / 2) * 6
          width  = 24
          height = 6
          properties = {
            title  = "Recent application errors"
            region = local.region
            view   = "table"
            query  = "SOURCE '${var.app_log_group_name}' | fields @timestamp, logger, message, request_id | filter level in [\"ERROR\", \"CRITICAL\"] | sort @timestamp desc | limit 20"
          }
        },
      ],
    )
  })
}

data "aws_region" "current" {}
