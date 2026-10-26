# IAM user that GitHub Actions uses to deploy.
# (GitHub OIDC would avoid long-lived keys, but the account's organization
# policy denies creating OIDC providers.) The user can ONLY deploy this app:
# push the backend image, restart the ECS service, upload the frontend,
# and clear the CloudFront cache. Create its access key in the console.
resource "aws_iam_user" "github_actions" {
  name = "github-actions-image-uploader"
}

resource "aws_iam_user_policy" "github_actions_deploy" {
  name = "deploy-image-uploader"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this action has no resource-level permissions
      },
      {
        Sid    = "EcrPushBackendImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = aws_ecr_repository.image_uploader_repo.arn
      },
      {
        Sid      = "EcsRedeployBackend"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = aws_ecs_service.image_uploader_backend.id # the service ARN
      },
      {
        Sid      = "S3ListFrontendBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.image_uploader_frontend.arn
      },
      {
        Sid      = "S3UploadFrontendFiles"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.image_uploader_frontend.arn}/*"
      },
      {
        Sid      = "CloudFrontClearCache"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = aws_cloudfront_distribution.image_uploader.arn
      },
    ]
  })
}

output "github_actions_user" {
  value = aws_iam_user.github_actions.name
}
