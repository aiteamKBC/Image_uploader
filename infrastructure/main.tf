resource "aws_ecs_cluster" "image_uploader" {
  name = "image-uploader-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_default_vpc" "image_uploader_vpc" {

}
resource "aws_default_subnet" "image_uploader_subnet_a" {
  availability_zone = "${var.aws_region}a"
}
resource "aws_default_subnet" "image_uploader_subnet_b" {
  availability_zone = "${var.aws_region}b"
}
resource "aws_default_subnet" "image_uploader_subnet_c" {
  availability_zone = "${var.aws_region}c"
}


