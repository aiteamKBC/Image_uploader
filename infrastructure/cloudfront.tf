# --- Lets CloudFront read the private bucket (console: "Allow private S3 bucket access") ---
resource "aws_cloudfront_origin_access_control" "image_uploader_frontend" {
  name                              = "image-uploader-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- AWS's ready-made policies (same names you picked in the console) ---
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# --- The distribution ---
resource "aws_cloudfront_distribution" "image_uploader" {
  enabled             = true
  comment             = "image-uploader"
  aliases             = [var.domain_name] # console: "Add domain"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"

  # Origin 1: the S3 bucket (React files)
  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.image_uploader_frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.image_uploader_frontend.id
  }

  # Origin 2: the load balancer (Django API)
  origin {
    origin_id   = "alb-backend"
    domain_name = aws_lb.image_uploader_alb.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # the ALB has no certificate
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
    }
  }

  # Default behavior: everything -> S3, cached
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # Behavior /api/* -> load balancer, never cached, all methods (upload, delete)
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-backend"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Error pages: React routes like /gallery
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  # HTTPS with your existing certificate
    viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# --- Bucket policy: ONLY this distribution may read the files ---
resource "aws_s3_bucket_policy" "image_uploader_frontend" {
  bucket = aws_s3_bucket.image_uploader_frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.image_uploader_frontend.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.image_uploader.arn }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.image_uploader_frontend]
}

output "cloudfront_domain" {
  description = "Point the Hostinger CNAME here"
  value       = aws_cloudfront_distribution.image_uploader.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.image_uploader.id
}
