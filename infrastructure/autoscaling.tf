# WHAT can scale, and between which limits
resource "aws_appautoscaling_target" "image_uploader_backend" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.image_uploader.name}/${aws_ecs_service.image_uploader_backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1 # never fewer than 1 task
  max_capacity       = 4 # never more than 4 (your cost ceiling)
}

# WHEN to scale: keep average CPU around 60%
resource "aws_appautoscaling_policy" "image_uploader_cpu" {
  name               = "image-uploader-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.image_uploader_backend.service_namespace
  resource_id        = aws_appautoscaling_target.image_uploader_backend.resource_id
  scalable_dimension = aws_appautoscaling_target.image_uploader_backend.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60  # aim for 60% average CPU
    scale_out_cooldown = 60  # after adding a task, wait 1 min before adding another
    scale_in_cooldown  = 300 # after removing a task, wait 5 min before removing another
  }
}
