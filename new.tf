// aws configure :

provider "aws" {
  version = "~> 2.69"
  region  = "ap-south-1"
}

// RSA private key :

variable "EC2_Key" {default="keyname111"}
resource "tls_private_key" "mynewkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

// AWS key-pair :

resource "aws_key_pair" "generated_key" {
  key_name   = var.EC2_Key
  public_key = tls_private_key.mynewkey.public_key_openssh
}
resource "aws_vpc" "my-vpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"
  
}

resource "aws_subnet" "my-subnet" {
  vpc_id     = "${aws_vpc.my-vpc.id}"
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = "true"

  
}
resource "aws_internet_gateway" "my-ig" {
  vpc_id = "${aws_vpc.my-vpc.id}"
}

resource "aws_route_table" "rt_tb" {
  vpc_id = "${aws_vpc.my-vpc.id}"

  route {
    
    gateway_id = "${aws_internet_gateway.my-ig.id}"
    cidr_block = "0.0.0.0/0"
  }
}


resource "aws_route_table_association" "rt_associate" {
  subnet_id      = aws_subnet.my-subnet.id
  route_table_id = aws_route_table.rt_tb.id
}

resource "aws_security_group" "my-sg" {
vpc_id = "${aws_vpc.my-vpc.id}"

ingress {
description = "NFS"
from_port = 2049
to_port = 2049
protocol = "tcp"
cidr_blocks = [ "0.0.0.0/0" ]
}

ingress {
description = "HTTP"
from_port = 80
to_port = 80
protocol = "tcp"
cidr_blocks = [ "0.0.0.0/0" ]
}

ingress {
description = "SSH"
from_port = 22
to_port = 22
protocol = "tcp"
cidr_blocks = [ "0.0.0.0/0" ]
}

egress {
from_port= 0
to_port = 0
protocol = "-1"
cidr_blocks = [ "0.0.0.0/0" ]
}

}

resource "aws_efs_file_system" "my-efs"{ 

}
resource "aws_efs_mount_target" "efs-tar" {
file_system_id = "${aws_efs_file_system.my-efs.id}"
subnet_id = "${aws_subnet.my-subnet.id}"
security_groups = ["${aws_security_group.my-sg.id}"]
}

resource "aws_instance" "myterraformos1" {
ami = "ami-0447a12f28fddb066"
instance_type = "t2.micro"
key_name      = var.EC2_Key
subnet_id = "${aws_subnet.my-subnet.id}"
vpc_security_group_ids = [ "${aws_security_group.my-sg.id}" ]

user_data = <<-EOF
      #! /bin/bash
	sudo su - root
	sudo yum install httpd -y
        sudo service httpd start
	sudo service httpd enable
 	sudo yum install git -y
        sudo yum install -y amazon-efs-utils 
        sudo mount -t efs "${aws_efs_file_system.my-efs.id}":/ /var/www/html
	mkfs.ext4 /dev/sdf	
	mount /dev/sdf /var/www/html
	sudo git clone https://github.com/aaditya2801/terraformjob1.git /var/www/html
	  
EOF
}

// S3 bucket :

resource "aws_s3_bucket" "s3bucketjob1" {
bucket = "mynewbucketforjob1"
acl    = "public-read"
}

// Putting Objects in mynewbucketforjob1 :

resource "aws_s3_bucket_object" "s3_object" {
  bucket = aws_s3_bucket.s3bucketjob1.bucket
  key    = "snapcode.png"
  source = "C:/Users/aadit/OneDrive/Desktop/snapcode.png"
  acl    = "public-read"
}

// Cloud Front Distribution :

locals {
s3_origin_id = aws_s3_bucket.s3bucketjob1.id
}

resource "aws_cloudfront_distribution" "CloudFrontAccess" {

depends_on = [
    aws_s3_bucket_object.s3_object,
  ]

origin {
domain_name = aws_s3_bucket.s3bucketjob1.bucket_regional_domain_name
origin_id   = local.s3_origin_id
}

enabled             = true
is_ipv6_enabled     = true
comment             = "s3bucket-access"

default_cache_behavior {
allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
viewer_protocol_policy = "allow-all"
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
}
# Cache behavior with precedence 0
ordered_cache_behavior {
path_pattern     = "/content/immutable/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD", "OPTIONS"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
headers      = ["Origin"]
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 86400
max_ttl                = 31536000
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
# Cache behavior with precedence 1
ordered_cache_behavior {
path_pattern     = "/content/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
price_class = "PriceClass_200"
restrictions {
geo_restriction {
restriction_type = "blacklist"
locations        = ["CA"]
}
}
tags = {
Environment = "production"
}
viewer_certificate {
cloudfront_default_certificate = true
}
retain_on_delete = true
}

// Changing the html code and adding the image url in that.

resource "null_resource" "addingurl"  {
depends_on = [
    aws_cloudfront_distribution.CloudFrontAccess,
  ]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mynewkey.private_key_pem
    host     = aws_instance.myterraformos1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
	"echo '<img src='https://${aws_cloudfront_distribution.CloudFrontAccess.domain_name}/snapcode.png' width='300' height='330'>' | sudo tee -a /var/www/html/index.html"
    ]
  }
}

// deploying webapp :

resource "null_resource" "deploywebapp"  {
depends_on = [
     null_resource.addingurl,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.myterraformos1.public_ip}/index.html"
  	}
}
