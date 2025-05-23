# --------------------------
# * TERRAFORM SYNTAX
# --------------------------

# resource "resource_type" "contextual_name"
#  {
#     name = "real_name"
#  }
#   --> contextual_name = how I'll refer to it in Terraform eg. aws_instance.contextual_name.id --> resource label used only the  .tf file
#   --> name = "name" →  name tag or setting used by AWS -->  attribute passed to AWS or the provider

# data "name" {} --> data block pulls read-only data from existing AWS resources , cannot be changed
# variable "name" {} --> Defines inputs into the Terraform config, can be user dfefined or script defined and can be changed 

# ---------------------------------------
# 0. Terrform configuration, variables
# ---------------------------------------

# Terraform configuration for AWS architecture using EC2, ALB, ASG, S3, and CloudFront
terraform {
  required_providers {  // lets terraform know which providers it should work with
    aws =  {            // need AWS provider so it can translate the terraform code into its values and config
      source = "hashicorp/aws"
      version = ">= 4.0.0, <= 5.0.0" // ensure versioning but keep it stable 
    }
  }
}

// supply a value for the region for the aws provider
provider "aws" {
  region = "eu-central-1"
}

// variable PORT=3000
variable "backend_port" {
  description = "The port the backend listens on"
  type        = number
  default     = 3000
}

variable "project" {
  default = "tf"
}

variable "environment" {
  default = "dev"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# gets data of the current AWS account to be able to associate resources with it 
data "aws_caller_identity" "current" {}

# get IP of the user to add them SSH access to the EC2 instances
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

# --------------------------
# 1. VPC, Subnets, IGW, etc.
# --------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16" // assign a larger cidr block to leave enough room for all subnets in the vpc
  
  tags = {
    Name        = "${var.project}-main-vpc"
    Project     = var.project
    Environment = var.environment
  }
}

# internet gateway for public subnets
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# public subnet has resources that are directly accessible from the internet, such as load balancers
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main.id # defines vpc to which the subnet belongs to
  cidr_block              = "10.0.3.0/24" # defines the IP address range for this subnet
  availability_zone       = "eu-central-1a" # availability zone where this subnet will be located
  map_public_ip_on_launch = true # ensures instances in this subnet get public IPs 

  tags = {
    Name        = "${var.project}-public-subnet-1"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"  # Specify the Availability Zone
  map_public_ip_on_launch = true # ensures instances in this subnet get public IPs 

  tags = {
    Name        = "${var.project}-public-subnet-2"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.project}-public-route-table"
    Project     = var.project
    Environment = var.environment
  }
}

# Add a route for the Internet Gateway
resource "aws_route" "internet_gateway_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"  # Default route to the internet
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "rt-association-1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "rt-association-2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --------------------------
# 2. Security Groups
# --------------------------

resource "aws_security_group" "ec2_security_group" {
  name = "${var.project}-ec2-security-group"
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project}-ec2-security-group"
    Project     = var.project
    Environment = var.environment
  }
}

data "aws_ec2_managed_prefix_list" "cloudfront_prefix_list" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb_security_group" {
  name   = "${var.project}-alb-security-group"
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project}-alb-security-group"
    Project     = var.project
    Environment = var.environment
  }
}

### rules ###

# ALB ingress - allow HTTP from cloudfront
resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_prefix_list.id]
  description     = "Allow HTTP traffic from CloudFront"
  security_group_id = aws_security_group.alb_security_group.id
}

# ALB egress to EC2 SG (optional — most leave this open)
resource "aws_security_group_rule" "alb_egress_to_ec2" {
  type                     = "egress"
  from_port                = var.backend_port
  to_port                  = var.backend_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2_security_group.id
  security_group_id        = aws_security_group.alb_security_group.id
}

# EC2 ingress from ALB SG
resource "aws_security_group_rule" "ec2_ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.backend_port
  to_port                  = var.backend_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_security_group.id
  security_group_id        = aws_security_group.ec2_security_group.id
}

# SSH ingress from user's IP
resource "aws_security_group_rule" "ec2_ssh_ingress_from_user_ip" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  cidr_blocks              = ["${chomp(data.http.my_ip.response_body)}/32"]
  security_group_id        = aws_security_group.ec2_security_group.id
}

# EC2 ingress on port 3000 from users IP
resource "aws_security_group_rule" "ec2_ingress_from_user" {
  type                     = "ingress"
  from_port                = var.backend_port
  to_port                  = var.backend_port
  protocol                 = "tcp"
  cidr_blocks              = ["${chomp(data.http.my_ip.response_body)}/32"]
  security_group_id        = aws_security_group.ec2_security_group.id
}

# EC2 egress - allow all
resource "aws_security_group_rule" "ec2_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2_security_group.id
}

# --------------------------
# 3/1. S3 Bucket for Frontend
# --------------------------
resource "aws_s3_bucket" "frontend_bucket" {
  # naming: username-project-frontend-bucket
  bucket = "${lower(split("/", data.aws_caller_identity.current.arn)[1])}-${var.project}-frontend-bucket" # gets the username and lowercases it for original s3 bucket name 
  
  tags = {
    Name        = "${lower(split("/", data.aws_caller_identity.current.arn)[1])}-${var.project}-frontend-bucket"
    Project     = var.project
    Environment = var.environment
  }
}

# block all public access
resource "aws_s3_bucket_public_access_block" "s3_public_access_block" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
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
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.cloudfront.id}"
          }
        }
      }
    ]
  })
}

# --------------------------
# 3/2. Application Load Balancer
# --------------------------
resource "aws_lb" "backend_alb" {
  name = "${var.project}-backend-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups    = [aws_security_group.alb_security_group.id]

  enable_deletion_protection = false
  
  tags = {
    Name        = "${var.project}-backend-alb"
    Project     = var.project
    Environment = var.environment
  }
  
}

# where the alb should forward requests
# target group is connected to the alb in the listener
resource "aws_lb_target_group" "backend_target_group" {
  name = "${var.project}-backend-target-group"
  port     = var.backend_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/api/health"
    protocol            = "HTTP"
    port                = "${var.backend_port}"
    interval            = 300
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project}-backend-target-group"
    Project     = var.project
    Environment = var.environment
  }
}

// alb listens http traffic (which will come only from cloudfront thanks to security group)
// if there were multiple target groups, multiple listener rules with different routes could be configured
resource "aws_lb_listener" "alb_backend_listener" {
  load_balancer_arn = aws_lb.backend_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_target_group.arn
  }

  tags = {
    Name        = "${var.project}-alb-backend-listener"
    Project     = var.project
    Environment = var.environment
  }
}

# --------------------------
# 4. CloudFront Distribution
# --------------------------

resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name = "${var.project}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cloudfront" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  tags = {
    Name        = "${var.project}-cloudfront"
    Project     = var.project
    Environment = var.environment
  }

  // must explicitly say "I do not want to restrict traffic based on any country" 
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Origin for S3 (Frontend)
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name // cannot be the website_endpoint, must be regional_domain_name when using cloudfront !!!
    origin_id   = "s3_frontend_origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
    s3_origin_config {
      origin_access_identity = "" # Must be empty string when using OAC
    }
    # custom_origin_config {
    #   http_port              = 80
    #   https_port             = 443
    #   origin_protocol_policy = "https-only"
    #   origin_ssl_protocols   = ["TLSv1.2"]
    # }
  }

  # 🌍 Default behavior (Frontend)
  default_cache_behavior {
    target_origin_id       = "s3_frontend_origin"
    viewer_protocol_policy = "allow-all"
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
    domain_name = aws_lb.backend_alb.dns_name
    origin_id   = "alb-backend-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Backend API on /api/* path
  ordered_cache_behavior {
    path_pattern           = "/api*"
    target_origin_id       = "alb-backend-origin"
    viewer_protocol_policy = "allow-all"
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
# 5. Launch Template
# --------------------------

# get the public SSH key and store it in aws
resource "aws_key_pair" "deployer" {
  key_name   = "EC2_SSH_KEY"
  public_key = file("./.keys/EC2_SSH_KEY.pub")
}

# attach the key to the EC2 instance
resource "aws_launch_template" "backend_launch_template" {
  name_prefix   = "${var.project}-backend-launch-template"
  image_id      = data.aws_ami.ubuntu.id # insert ubuntu ami and run user data script to get docker and needed files in it from my created dockerfile
  instance_type = "t2.micro"
  key_name = aws_key_pair.deployer.key_name # to gain SSH access to the EC2 instances

  lifecycle { // avoids downtime by creating a new template before destroying the old one during changes
    create_before_destroy = true
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.ec2_security_group.id]
  }

# startup script that runs when the EC2 instance first boots, injecting needed terraform variables 
  user_data = base64encode(templatefile("./user_data.sh.tpl", {
    backend_port  = var.backend_port,
    frontend_origin = aws_cloudfront_distribution.cloudfront.domain_name # backend code depends on FRONTEND_ORIGIN for CORS
  }))

  tags = {
    Name        = "${var.project}-backend-launch-template"
    Project     = var.project
    Environment = var.environment
  }
}

# --------------------------
# 7. Auto Scaling Group
# --------------------------
resource "aws_autoscaling_group" "backend_asg" {
  name = "${var.project}-backend-asg"
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  health_check_type    = "ELB" // makes sure the instance is considered healthy by ALB
  health_check_grace_period = 300 // time in seconds that Auto Scaling should wait after launching an instance before checking its health
  vpc_zone_identifier  = [aws_subnet.public_subnet_1.id]
  target_group_arns    = [aws_lb_target_group.backend_target_group.arn]
  depends_on = [aws_launch_template.backend_launch_template]

  launch_template {
    id      = aws_launch_template.backend_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-ec2-backend-instance"
    propagate_at_launch = true
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------
# 7. End messages and outputs
# --------------------------

# exporting created values needed for CORS
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cloudfront.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend_bucket.bucket
  description = "The name of the S3 bucket used for the frontend"
}