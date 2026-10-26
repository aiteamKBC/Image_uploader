# Task definition = the "recipe" for the container (console: Task definitions -> Create)
resource "aws_ecs_task_definition" "image_uploader_backend" {
  family                   = "image-uploader-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required for Fargate
  cpu                      = 1024     # 1 vCPU
  memory                   = 3072     # 3 GB
  execution_role_arn       = aws_iam_role.image_uploader_task_execution.arn
  task_role_arn            = aws_iam_role.image_uploader_task.arn # X-Ray access (iam.tf)

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "backend"
    image     = "${aws_ecr_repository.image_uploader_repo.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 8023 # Gunicorn's port (backend/Dockerfile)
      protocol      = "tcp"
    }]

    environment = [
      { name = "SUPABASE_URL", value = var.supabase_url },
      { name = "SUPABASE_KEY", value = var.supabase_key },
      # Filled in automatically - no more copy-pasting the ALB address
      { name = "DJANGO_ALLOWED_HOSTS", value = aws_lb.image_uploader_alb.dns_name },

      # Tracing: setting the OTLP endpoint makes the Dockerfile start Gunicorn through
      # `opentelemetry-instrument`; spans go to the collector sidecar below, then X-Ray
      { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://127.0.0.1:4318" },
      # Use the AWS distro's setup (X-Ray sampler etc.), not the plain OpenTelemetry one
      { name = "OTEL_PYTHON_DISTRO", value = "aws_distro" },
      { name = "OTEL_PYTHON_CONFIGURATOR", value = "aws_configurator" },
      { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/protobuf" },
      { name = "OTEL_RESOURCE_ATTRIBUTES", value = "service.name=${local.xray_service_name}" },
      # Sample with the X-Ray rules in observability.tf (fetched through the collector)
      { name = "OTEL_TRACES_SAMPLER", value = "xray" },
      { name = "OTEL_TRACES_SAMPLER_ARG", value = "endpoint=http://127.0.0.1:2000" },
      { name = "OTEL_PROPAGATORS", value = "xray,tracecontext,baggage" },
      { name = "OTEL_PYTHON_ID_GENERATOR", value = "xray" },
      # Traces only: no custom metrics or logs (they would cost extra)
      { name = "OTEL_METRICS_EXPORTER", value = "none" },
      { name = "OTEL_LOGS_EXPORTER", value = "none" },
      { name = "OTEL_AWS_APPLICATION_SIGNALS_ENABLED", value = "false" },
      # Don't trace the ALB health checks (one every 30s per task)
      { name = "OTEL_PYTHON_DJANGO_EXCLUDED_URLS", value = "health" },
      # The Django instrumentation needs this before wsgi.py runs
      { name = "DJANGO_SETTINGS_MODULE", value = "config.settings" },
    ]

    # Start after the collector, so the first requests' traces aren't lost
    dependsOn = [{ containerName = "aws-otel-collector", condition = "START" }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.image_uploader_backend.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
    },
    # Sidecar: AWS Distro for OpenTelemetry collector. Receives the app's spans on
    # localhost and sends them to X-Ray. Not essential: if it crashes, the app keeps
    # serving (only tracing stops).
    {
      name      = "aws-otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.50.0"
      essential = false

      environment = [
        { name = "AOT_CONFIG_CONTENT", value = local.otel_collector_config },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.image_uploader_backend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "otel"
        }
      }
  }])
}

# Service = "keep N copies of the task running, attached to the load balancer"
resource "aws_ecs_service" "image_uploader_backend" {
  name            = "iu-backend"
  cluster         = aws_ecs_cluster.image_uploader.id
  task_definition = aws_ecs_task_definition.image_uploader_backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_default_subnet.image_uploader_subnet_a.id,
      aws_default_subnet.image_uploader_subnet_b.id,
      aws_default_subnet.image_uploader_subnet_c.id,
    ]
    security_groups  = [aws_security_group.image_uploader_sg.id]
    assign_public_ip = true # no NAT gateway -> needs a public IP to reach ECR/Supabase
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.image_uploader_tg.arn
    container_name   = "backend" # must match the name in the task definition
    container_port   = 8023
  }

  # If a new version never becomes healthy, go back to the previous one
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  # The autoscaler changes desired_count at runtime - don't reset it on apply
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.image_uploader_http]
}

  
