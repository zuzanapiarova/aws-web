#!/bin/bash

# THIS SCRIPT IS EXECUTED EACH TIME A NEW EC2 INSTANCE IS CREATED BY ASG AS ROOT OF THE EC2
# quit execution when any error is encountered
set -e

# Update and install required packages
apt update -y
apt install -y ca-certificates curl gnupg lsb-release

# set up Docker repository key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc

# add Docker apt repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# install Docker engine
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# enable and start Docker
systemctl enable docker
systemctl start docker

# pull and run the Docker image
docker pull zuzanapiarova/cloud-programming-backend-image:latest
docker run -d --restart always -p ${backend_port}:${backend_port} \
-e PORT=${backend_port} \
-e FRONTEND_ORIGIN=https://${frontend_origin} \ 
zuzanapiarova/backend-image:latest 