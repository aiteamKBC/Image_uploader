variable "aws_region" {
  default = "eu-north-1"
}
variable "supabase_url" {
  description = "SUPABASE_URL from backend/.env"
  type        = string
  sensitive   = true # hidden in terraform plan/apply output
}

variable "supabase_key" {
  description = "SUPABASE_KEY from backend/.env"
  type        = string
  sensitive   = true
}
variable "certificate_arn" {
  description = "Existing ACM certificate (us-east-1) for *.kentbusinesscollege.net - created outside Terraform, never delete it"
  type        = string
  default     = "arn:aws:acm:us-east-1:298490729551:certificate/039ab00b-eb26-4757-94fa-ccccc1e93afa"
}

variable "domain_name" {
  type    = string
  default = "image-uploader-aws.kentbusinesscollege.net"
}
