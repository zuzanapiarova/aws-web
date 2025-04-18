# --------------------------
# * TERRAFORM SYNTAX
# --------------------------

# resource "resource_type" "contextual_name"
#  {
#     name = "real_name"
#  }
#   --> contextual_name = how I'll refer to it in Terraform eg. aws_instance.contextual_name.id --> resource label used only the  .tf file
#   --> name = "name" →  name tag or setting used by AWS -->  attribute passed to AWS or the provider


# ---------------------------------------
# 0. Terrform configuration and variables
# ---------------------------------------

# Terraform configuration for AWS architecture using EC2, ALB, ASG, S3, and CloudFront
terraform {
  required_providers {  // lets terraform know which providers it should work with
    aws =  {            // need AWS provider so it can translate the terraform code into its values and config
      source = "hashicorp/aws"
      version = ">= 3.5.0, < 4.0.0" // ensure versioning but keep it stable 
    }
  }
}

// supply a value for the region for the aws provider
provider "aws" {
  region = "eu-central-1"
}

// variable PORT=3000
variable "backend-port" {
  description = "The port the backend listens on"
  type        = number
  default     = 3000
}

# --------------------------
# 1. VPC, Subnets, IGW, etc.
# --------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16" // typically assign a lkarger cidr block and should leave enough room for all subnets in the vpc
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

// has resources that are directly accessible from the internet, such as load balancers
resource "aws_subnet" "public-subnet" {
  vpc_id                  = aws_vpc.main.id // defines vpc to which teh subnet belongs to
  cidr_block              = "10.0.1.0/24" // defines the IP address range for this subnet
  availability_zone       = "eu-central-1a" // availability zone where this subnet will be located
  map_public_ip_on_launch = true
}

// private subnets are necessary for instances that shouldn't be directly accessible from the internet (e.g., backend servers that shouldn't be exposed).
// instances in a private subnet do not have direct access to the internet
resource "aws_subnet" "private-subnet" {
  vpc_id                  = aws_vpc.main.id // defines vpc to which teh subnet belongs to
  cidr_block              = "10.0.2.0/24" // defines the IP address range for this subnet - 10.0.0.0/8 is reserved for private subnets
  availability_zone       = "eu-central-1a" // availability zone where this subnet will be located
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.public.id
}

# --------------------------
# 2. Security Groups
# --------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group_rule" "allow_cloudfront" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb-security-group.id
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  description       = "Allow CloudFront only"
}

// TODO: change them accordingly to my rules
resource "aws_security_group" "alb-security-group" {
  name   = "alb-security-group"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2-security-group" {
  name   = "ec2-security-group"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = var.backend-port
    to_port         = var.backend-port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb-security-group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --------------------------
# 3. S3 Bucket for Frontend
# --------------------------
resource "aws_s3_bucket" "frontend-bucket" {
  bucket = "frontend-bucket"
}

// block all public access
resource "aws_s3_bucket_public_access_block" "s3-public-access-block" {
  bucket = aws_s3_bucket.frontend-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// TODO: change to policy allowing only cloudfront
resource "aws_s3_bucket_policy" "frontend-bucket-policy" {
  bucket = aws_s3_bucket.frontend-bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccessOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend-bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.cloudfront.id}"
          }
        }
      }
    ]
  })
}

// THEN: when the infrastructure is built, run:
// aws s3 sync ./build-folder-path s3://frontend-bucket --delete // --delete removes old files not in the new build

# --------------------------
# 4. CloudFront Distribution
# --------------------------

resource "aws_cloudfront_origin_access_control" "frontend-oac" {
  name                              = "frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cloudfront" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  // must explicitly say "I do not want to restrict traffic based on any country" 
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Origin for S3 (Frontend)
  origin {
    domain_name = aws_s3_bucket.frontend-bucket.bucket_regional_domain_name // cannot be the website_endpoint, must be regional_domain_name when using cloudfront !!!
    origin_id   = "s3-frontend-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend-oac.id
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  # 🌍 Default behavior (Frontend)
  default_cache_behavior {
    target_origin_id       = "s3-frontend-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    compress = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # Origin for ALB (Backend API)
  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "alb-backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 🔧 Backend API (e.g., /api/*)
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-backend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    compress = true # Good for API responses 

  forwarded_values {
    query_string = true
    headers      = ["*"] # Needed if your backend depends on headers (e.g., auth)
    cookies {
      forward = "all" # Or "whitelist" specific ones
    }
  }

  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 0
  }

  # SSL Certificate (Use default or ACM for custom domain)
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# --------------------------
# 5. Application Load Balancer
# --------------------------
resource "aws_lb" "backend-alb" {
  name               = "backend-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public-subnet.id]
  security_groups    = [aws_security_group.alb-security-group.id]

  enable_deletion_protection = false
}

// where the alb should forward requests
resource "aws_lb_target_group" "backend-target-group" {
  name     = "backend-target-group"
  port     = var.backend-port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/api/health"
    protocol            = "HTTP"
    port                = "${var.backend-port}"
    interval            = 300
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

// alb listens http traffic (which will come only from cloudfront thanks to security group)
// if there were multiple target groups, multiple listener rules with different routes could be configured
resource "aws_lb_listener" "alb-backend-listener" {
  load_balancer_arn = aws_lb.backend-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend-target-group.arn
  }
}

# --------------------------
# 5. Launch Template
# --------------------------

// TODO: create AMI
variable "backend-ami-id" {
  description = "AMI ID for Ubuntu with Docker" // todo
  type        = string
}

// TODO: how do i input it in with terrform.tfvars?
variable "ec2-ssh-key-name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

resource "aws_launch_template" "backend-launch-template" {
  name_prefix   = "backend-launch-template"
  image_id      = var.backend-ami-id // TODO: backend-ami
  instance_type = "t2.micro"
  key_name      = var.ec2-ssh-key-name

  lifecycle { // avoids downtime by creating a new template before destroying the old one during changes
    create_before_destroy = true
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.ec2-security-group.id]
  }

// startup script that runs when the EC2 instance first boots
// installs docker and 
user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e

              apt update -y
              apt install -y ca-certificates curl gnupg lsb-release
              sudo install -m 0755 -d /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
              chmod a+r /etc/apt/keyrings/docker.asc

              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
              https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
              
              apt update -y
              apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
              systemctl enable docker
              systemctl start docker

              docker pull zuzanapiarova/backend-image:latest
              docker run -d --restart always -p \${var.backend-port}:${var.backend-port} \
                -e PORT=\${var.backend-port} \
                -e FRONTEND_ORIGIN=https://\${aws_cloudfront_distribution.cdn.domain_name} \\
              zuzanapiarova/backend-image:latest
              EOF
            )
}

# --------------------------
# 7. Auto Scaling Group
# --------------------------
resource "aws_autoscaling_group" "backend-asg" {
  name = "backend-asg"
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  health_check_type    = "ELB" // makes sure the instance is considered healthy by ALB
  health_check_grace_period = 120 // time in seconds that Auto Scaling should wait after launching an instance before checking its health
  vpc_zone_identifier  = [aws_subnet.private-subnet.id]
  target_group_arns    = [aws_lb_target_group.backend-target-group.arn]

  launch_template {
    id      = aws_launch_template.backend-launch-template.id
    version = "$Latest"
  }

  // tag it in aws with this information
  tag {
    key                 = "Name"
    value               = "backend-instance"
    propagate_at_launch = true
  }
  
  lifecycle {
    create_before_destroy = true
  }
}