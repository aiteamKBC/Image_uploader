# Private bucket for the built React files (console: S3 -> Create bucket)
resource "aws_s3_bucket" "image_uploader_frontend" {
  bucket        = "kbc-image-uploader-frontend" # must be unique across all of AWS
  force_destroy = true                          # contents are build output; lets terraform destroy empty it
}

# "Block all public access" = ON (only CloudFront will read it, in step 7)
resource "aws_s3_bucket_public_access_block" "image_uploader_frontend" {
  bucket                  = aws_s3_bucket.image_uploader_frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "frontend_bucket" {
  value = aws_s3_bucket.image_uploader_frontend.bucket
}
