# Docker image registry for the backend
resource "aws_ecr_repository" "image_uploader_repo" {
  name                 = "image_uploader"
  image_tag_mutability = "MUTABLE" # we re-push the same :latest tag on every update
  force_delete         = true      # lets `terraform destroy` remove it even with images inside
}

# Keep only the 10 newest images, so old ones don't cost storage forever
resource "aws_ecr_lifecycle_policy" "image_uploader_repo" {
  repository = aws_ecr_repository.image_uploader_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# Printed after apply, so you can copy the address for docker push
output "ecr_repository_url" {
  value = aws_ecr_repository.image_uploader_repo.repository_url
}
