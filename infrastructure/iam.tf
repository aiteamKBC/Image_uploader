# Role that ECS itself uses to START your task:
# pull the image from ECR and send the container's logs to CloudWatch.
resource "aws_iam_role" "image_uploader_task_execution" {
  name = "image-uploader-task-execution"

  # "Trust policy": WHO may use this role -> only the ECS tasks service
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# WHAT the role may do -> AWS's ready-made policy (ECR pull + CloudWatch logs)
resource "aws_iam_role_policy_attachment" "image_uploader_task_execution" {
  role       = aws_iam_role.image_uploader_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Role the RUNNING containers use to call AWS (the execution role above only starts them):
# the ADOT collector sidecar sends traces to X-Ray and reads the sampling rules.
resource "aws_iam_role" "image_uploader_task" {
  name = "image-uploader-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS's ready-made policy: PutTraceSegments + GetSamplingRules/Targets, nothing else
resource "aws_iam_role_policy_attachment" "image_uploader_task_xray" {
  role       = aws_iam_role.image_uploader_task.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# Where the container's output (Gunicorn logs, errors) goes
resource "aws_cloudwatch_log_group" "image_uploader_backend" {
  name              = "/ecs/image-uploader"
  retention_in_days = 14 # delete logs older than 2 weeks, so they don't cost forever
}
