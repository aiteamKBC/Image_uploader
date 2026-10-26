# ------------------------------------------------------------
# Observability: X-Ray tracing + CloudWatch alarms and dashboard
#   Traces : app (OpenTelemetry) -> collector sidecar (ecs.tf) -> X-Ray
#   Metrics: ALB, ECS and CloudFront metrics AWS already collects (free),
#            plus Container Insights on the cluster (main.tf)
#   Alarms : email through SNS when something breaks
# ------------------------------------------------------------

locals {
  # The name the service gets in X-Ray's trace map
  xray_service_name = "image-uploader-backend"

  # ADOT collector config, passed to the sidecar as AOT_CONFIG_CONTENT.
  # Everything listens on 127.0.0.1 only: the app shares the task's localhost.
  otel_collector_config = yamlencode({
    extensions = {
      # Lets the app read the X-Ray sampling rules below (OTEL_TRACES_SAMPLER=xray)
      awsproxy = { endpoint = "127.0.0.1:2000", region = var.aws_region }
    }
    receivers = {
      otlp = { protocols = { http = { endpoint = "127.0.0.1:4318" } } }
    }
    processors = {
      batch = {}
    }
    exporters = {
      awsxray = { region = var.aws_region }
    }
    service = {
      extensions = ["awsproxy"]
      pipelines = {
        traces = {
          receivers  = ["otlp"]
          processors = ["batch"]
          exporters  = ["awsxray"]
        }
      }
    }
  })

  # Dimensions used by the alarms and dashboard
  alb_dimensions = { LoadBalancer = aws_lb.image_uploader_alb.arn_suffix }
  tg_dimensions = {
    LoadBalancer = aws_lb.image_uploader_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.image_uploader_tg.arn_suffix
  }
  ecs_dimensions = {
    ClusterName = aws_ecs_cluster.image_uploader.name
    ServiceName = aws_ecs_service.image_uploader_backend.name
  }
}

# ---------------- X-Ray ----------------

# Which requests get traced: the first request every second, plus 10% of the rest.
# At this app's traffic that is nearly every request; under a load test it caps the
# cost (first 100,000 traces a month are free, then $5 per million).
# Change it here, or in the console (X-Ray -> Sampling rules) without a redeploy.
resource "aws_xray_sampling_rule" "image_uploader" {
  rule_name      = "image-uploader"
  priority       = 100 # lower = checked first; the built-in Default rule is 10000
  version        = 1
  reservoir_size = 1   # traces per second, always taken
  fixed_rate     = 0.1 # share of the requests above that
  service_name   = local.xray_service_name
  service_type   = "*"
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  resource_arn   = "*"
}

# ---------------- Notifications ----------------

resource "aws_sns_topic" "image_uploader_alarms" {
  name = "image-uploader-alarms"
}

# Only created when alarm_email is set in terraform.tfvars
resource "aws_sns_topic_subscription" "image_uploader_alarms_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.image_uploader_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------- Alarms ----------------
# Each one evaluates 1-minute data points and fires when M out of the last N breach,
# so one slow minute doesn't wake anyone up. Thresholds are based on the load tests
# (upload p95 ~1.5 s, list p95 ~0.6 s at normal traffic); tune them as you learn.

# The app returned 5xx (e.g. 502 when Supabase fails)
resource "aws_cloudwatch_metric_alarm" "app_5xx" {
  alarm_name          = "image-uploader-app-5xx"
  alarm_description   = "Django returned 5 or more 5xx responses a minute (often Supabase errors). Check the logs and X-Ray traces."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.tg_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching" # no data = no errors
  alarm_actions       = [aws_sns_topic.image_uploader_alarms.arn]
  ok_actions          = [aws_sns_topic.image_uploader_alarms.arn]
}

# The load balancer itself returned 5xx (502/503/504: no healthy task, task crashed or timed out)
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "image-uploader-alb-5xx"
  alarm_description   = "The load balancer returned 5 or more 5xx a minute: tasks are down, crashing or timing out."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.image_uploader_alarms.arn]
  ok_actions          = [aws_sns_topic.image_uploader_alarms.arn]
}

# Slow responses. p95, not Average: an average hides the slow tail users feel.
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "image-uploader-latency-p95"
  alarm_description   = "95% of API requests should finish within 3 s; they haven't for 3 of the last 5 minutes. Check X-Ray for the slow segment."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime" # seconds
  dimensions          = local.tg_dimensions
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 3
  treat_missing_data  = "notBreaching" # no traffic = nothing slow
  alarm_actions       = [aws_sns_topic.image_uploader_alarms.arn]
  ok_actions          = [aws_sns_topic.image_uploader_alarms.arn]
}

# No task is passing the /health/ check: the API is down
resource "aws_cloudwatch_metric_alarm" "no_healthy_tasks" {
  alarm_name          = "image-uploader-no-healthy-tasks"
  alarm_description   = "No backend task passes /health/ - the API is down. Check ECS events and the container logs."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching" # no data from the health check = assume down
  alarm_actions       = [aws_sns_topic.image_uploader_alarms.arn]
  ok_actions          = [aws_sns_topic.image_uploader_alarms.arn]
}

# CPU stays high even though autoscaling (target 60%) should have added tasks:
# usually means it is already at max_capacity (4)
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "image-uploader-cpu-high"
  alarm_description   = "Service CPU above 85% for 5 minutes - autoscaling is probably at its 4-task maximum."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching" # a stopped service is caught by no_healthy_tasks
  alarm_actions       = [aws_sns_topic.image_uploader_alarms.arn]
  ok_actions          = [aws_sns_topic.image_uploader_alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "image-uploader-memory-high"
  alarm_description   = "Service memory above 85% for 5 minutes - risk of tasks being killed (out of memory)."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.image_uploader_alarms.arn]
  ok_actions          = [aws_sns_topic.image_uploader_alarms.arn]
}

# ---------------- Dashboard ----------------
# CloudWatch -> Dashboards -> image-uploader

locals {
  alb = aws_lb.image_uploader_alb.arn_suffix
  tg  = aws_lb_target_group.image_uploader_tg.arn_suffix
  cl  = aws_ecs_cluster.image_uploader.name
  svc = aws_ecs_service.image_uploader_backend.name
}

resource "aws_cloudwatch_dashboard" "image_uploader" {
  dashboard_name = "image-uploader"

  dashboard_body = jsonencode({
    periodOverride = "inherit"
    widgets = [
      # Row 1: alarm states at a glance
      {
        type = "alarm", x = 0, y = 0, width = 24, height = 3
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.no_healthy_tasks.arn,
            aws_cloudwatch_metric_alarm.app_5xx.arn,
            aws_cloudwatch_metric_alarm.alb_5xx.arn,
            aws_cloudwatch_metric_alarm.latency_p95.arn,
            aws_cloudwatch_metric_alarm.ecs_cpu_high.arn,
            aws_cloudwatch_metric_alarm.ecs_memory_high.arn,
          ]
        }
      },
      # Row 2: API traffic and latency (ALB)
      {
        type = "metric", x = 0, y = 3, width = 12, height = 6
        properties = {
          title  = "API requests and errors (per minute)"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb, { label = "Requests" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { label = "4xx from app" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { label = "5xx from app", color = "#d62728" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", ".", { label = "5xx from load balancer", color = "#ff7f0e" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 3, width = 12, height = 6
        properties = {
          title  = "API response time (seconds)"
          region = var.aws_region
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", local.tg, "LoadBalancer", local.alb, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
          annotations = { horizontal = [{ label = "p95 alarm", value = 3 }] }
        }
      },
      # Row 3: the ECS service
      {
        type = "metric", x = 0, y = 9, width = 12, height = 6
        properties = {
          title  = "Backend CPU and memory (%)"
          region = var.aws_region
          period = 60
          view   = "timeSeries"
          yAxis  = { left = { min = 0, max = 100 } }
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cl, "ServiceName", local.svc, { stat = "Average", label = "CPU avg" }],
            ["...", { stat = "Maximum", label = "CPU max" }],
            [".", "MemoryUtilization", ".", ".", ".", ".", { stat = "Average", label = "Memory avg" }],
          ]
          annotations = { horizontal = [{ label = "autoscaling target", value = 60 }] }
        }
      },
      {
        type = "metric", x = 12, y = 9, width = 12, height = 6
        properties = {
          title  = "Tasks: running vs healthy"
          region = var.aws_region
          period = 60
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cl, "ServiceName", local.svc, { stat = "Average", label = "Running (Container Insights)" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb, { stat = "Minimum", label = "Healthy in load balancer" }],
          ]
        }
      },
      # Row 4: CloudFront (its metrics only exist in us-east-1) and recent errors
      {
        type = "metric", x = 0, y = 15, width = 12, height = 6
        properties = {
          title  = "CloudFront: requests and error rate"
          region = "us-east-1"
          period = 300
          view   = "timeSeries"
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.image_uploader.id, "Region", "Global", { stat = "Sum", label = "Requests (5 min)" }],
            [".", "4xxErrorRate", ".", ".", ".", ".", { stat = "Average", label = "4xx %", yAxis = "right" }],
            [".", "5xxErrorRate", ".", ".", ".", ".", { stat = "Average", label = "5xx %", yAxis = "right" }],
          ]
        }
      },
      {
        type = "log", x = 12, y = 15, width = 12, height = 6
        properties = {
          title  = "Recent errors in the backend logs"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.image_uploader_backend.name}' | fields @timestamp, @logStream, @message | filter @message like /(?i)(error|exception|traceback|critical)/ | sort @timestamp desc | limit 50"
        }
      },
    ]
  })
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.image_uploader.dashboard_name}"
}

output "xray_trace_map_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#xray:service-map/map"
}
