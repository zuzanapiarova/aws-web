#!/bin/bash

# ! execute from the root of the cloned github repository

set -e # exit immediately if any command fails (non-zero exit code), with Terraform still showing the error output in the terminal

echo "Ensure you are executing this project from the root of the cloned GitHub repository !"

# need an EC2 SSH key access - create public(.pub)-private() key pair and store it in ./keys/EC2_SSH_KEY ⚠️ Never share the private key. Keep it safe!
mkdir -p .keys
ssh-keygen -t rsa -b 4096 -f ./.keys/EC2_SSH_KEY
chmod 400 ./.keys/EC2_SSH_KEY.pub

echo "Initializing a Terraform project"
terraform init

# I run validation when creating this file, other users do not have to
# echo "Validating Terraform files"
# terraform validate

# avoiding the Circular Dependency between Cloudfront and S3 Bucket Policy - policy depends on cloudfront id, but cloudfront depends on the S3 bucket origin
echo "Step 1: Creating S3 bucket (without policy)"
terraform apply -target=aws_s3_bucket.frontend-bucket -auto-approve
echo "Step 2: Creating CloudFront distribution"
terraform apply -target=aws_cloudfront_distribution.cloudfront -auto-approve
echo "Step 3: Applying all remaining infrastructure (including bucket policy and lunch template using the AMI)"
terraform apply -auto-approve
echo "All infrastructure created successfully!"

# WHEN THE INFRASTRUCTURE IS BUILT, NEED TO PROVIDE THE FRONTEND FILES
# create needed variables on which the frontend/backend depends on for CORS 
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
echo "CloudFront domain: $CLOUDFRONT_DOMAIN"
echo "Frontend bucket: $FRONTEND_BUCKET"

# make sure the user is in correct repository
if [ ! -d "frontend" ]; then
  echo "❌❌❌ Frontend directory not found. Make sure you are running this script from the root of the cloned GitHub repo. ❌❌❌"
  exit 1
fi

# build frontend witht the proper variable for API_URL
cd frontend
echo "REACT_APP_API_URL=$CLOUDFRONT_DOMAIN/api" > .env
npm install
npm run build

# import the build files into s3 with proper name of the S3 bucket
aws s3 sync ./build s3://$FRONTEND_BUCKET --delete # --delete removes old files not in the new build





# AMI is dependent on cloudfront and has to be created before launch template
# AMI needs one .env - FRONTEND_ORIGIN, which is the Cloudfront origin domain
# once cloudfront is created, we can create a docker image from the backend and pass it the 
# and create ami from the docker image 
# Allow others to input their AMI ID by setting it as a variable that the user can set in the terraform.tfvars file or through other means.