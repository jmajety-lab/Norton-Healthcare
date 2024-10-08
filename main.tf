provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us-east-2"
  region = "us-east-2"
}

# Create a VPC in us-east-1
resource "aws_vpc" "norton_vpc" {
  provider   = aws.us-east-1
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "norton-vpc"
  }
}

# Create subnets in us-east-1
resource "aws_subnet" "public_subnet_1a" {
  provider                  = aws.us-east-1
  vpc_id                    = aws_vpc.norton_vpc.id
  cidr_block                = "10.0.1.0/24"
  map_public_ip_on_launch   = true
  availability_zone         = "us-east-1a"
  tags = {
    Name = "public-subnet-1a"
  }
}

resource "aws_subnet" "public_subnet_1b" {
  provider                  = aws.us-east-1
  vpc_id                    = aws_vpc.norton_vpc.id
  cidr_block                = "10.0.3.0/24"
  map_public_ip_on_launch   = true
  availability_zone         = "us-east-1b"
  tags = {
    Name = "public-subnet-1b"
  }
}

# Create an Internet Gateway in us-east-1
resource "aws_internet_gateway" "igw" {
  provider = aws.us-east-1
  vpc_id   = aws_vpc.norton_vpc.id
  tags = {
    Name = "internet-gateway"
  }
}

# Create a Route Table in us-east-1
resource "aws_route_table" "public_rt" {
  provider = aws.us-east-1
  vpc_id   = aws_vpc.norton_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Route Table with Subnet in us-east-1
resource "aws_route_table_association" "public_rt_assoc_1a" {
  provider        = aws.us-east-1
  subnet_id       = aws_subnet.public_subnet_1a.id
  route_table_id  = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_1b" {
  provider        = aws.us-east-1
  subnet_id       = aws_subnet.public_subnet_1b.id
  route_table_id  = aws_route_table.public_rt.id
}

# Security Group in us-east-1
resource "aws_security_group" "web_sg" {
  provider = aws.us-east-1
  vpc_id   = aws_vpc.norton_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# IAM Role in us-east-1
resource "aws_iam_role" "ec2_role" {
  provider = aws.us-east-1
  name     = "ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM Role Policy in us-east-1
resource "aws_iam_role_policy" "ec2_policy" {
  provider = aws.us-east-1
  name     = "ec2-policy"
  role     = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "ec2:Describe*",
      Effect   = "Allow",
      Resource = "*"
    }]
  })
}

# IAM Instance Profile in us-east-1
resource "aws_iam_instance_profile" "ec2_profile" {
  provider = aws.us-east-1
  name     = "ec2-profile"
  role     = aws_iam_role.ec2_role.name
}

# EC2 Instances in us-east-1 Web server
resource "aws_instance" "web_instance_1a_1" {
  provider                 = aws.us-east-1
  ami                      = "ami-0b72821e2f351e396" # Amazon Linux 2 AMI
  instance_type            = "t2.micro"
  subnet_id                = aws_subnet.public_subnet_1a.id
  vpc_security_group_ids   = [aws_security_group.web_sg.id]
  iam_instance_profile     = aws_iam_instance_profile.ec2_profile.name
 

  tags = {
    Name = "web-instance-1a-1"
  }
}

# EC2 Instances in us-east-1 Application server

resource "aws_instance" "web_instance_1a_2" {
  provider                 = aws.us-east-1
  ami                      = "ami-0b72821e2f351e396" # Amazon Linux 2 AMI
  instance_type            = "t2.micro"
  subnet_id                = aws_subnet.public_subnet_1a.id
  vpc_security_group_ids   = [aws_security_group.web_sg.id]
  iam_instance_profile     = aws_iam_instance_profile.ec2_profile.name
   user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd mysql
              systemctl start httpd
              systemctl enable httpd
              echo "Hello World from $(hostname -f)" > /var/www/html/index.html
              echo "RDS Endpoint: ${aws_db_instance.default.endpoint}" >> /var/www/html/index.html
              EOF

  tags = {
    Name = "web-instance-1a-2"
  }
}

# Auto Scaling Group for Web Instances in us-east-1a
resource "aws_autoscaling_group" "web_asg_us_east_1a" {
  provider                 = aws.us-east-1
  desired_capacity         = 2
  max_size                 = 4
  min_size                 = 1
  vpc_zone_identifier      = [aws_subnet.public_subnet_1a.id] # us-east-1a
  launch_configuration     = aws_launch_configuration.web_lc_us_east_1a.id
  target_group_arns        = [aws_lb_target_group.web_tg_us_east_1.id]
  

  tag {
    key                    = "Name"
    value                  = "web-instance"
    propagate_at_launch    = true
  }
}

# Launch Configuration for ASG in us-east-1a
resource "aws_launch_configuration" "web_lc_us_east_1a" {
  provider                  = aws.us-east-1
  image_id                  = "ami-0b72821e2f351e396"
  instance_type             = "t2.micro"
  security_groups           = [aws_security_group.web_sg.id]
  iam_instance_profile      = aws_iam_instance_profile.ec2_profile.name

  lifecycle {
    create_before_destroy   = true
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello World from $(hostname -f)" > /var/www/html/index.html
              EOF
}

# Create VPC, Subnet, and Resources in us-east-2
resource "aws_vpc" "norton_vpc_us_east_2" {
  provider   = aws.us-east-2
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "norton-vpc-us-east-2"
  }
}

resource "aws_subnet" "public_subnet_us_east_2a" {
  provider                  = aws.us-east-2
  vpc_id                    = aws_vpc.norton_vpc_us_east_2.id
  cidr_block                = "10.0.1.0/24"
  map_public_ip_on_launch   = true
  availability_zone         = "us-east-2a"
  tags = {
    Name = "public-subnet-us-east-2a"
  }
}

resource "aws_internet_gateway" "igw_us_east_2" {
  provider = aws.us-east-2
  vpc_id   = aws_vpc.norton_vpc_us_east_2.id
  tags = {
    Name = "internet-gateway-us-east-2"
  }
}

resource "aws_route_table" "public_rt_us_east_2" {
  provider = aws.us-east-2
  vpc_id   = aws_vpc.norton_vpc_us_east_2.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_us_east_2.id
  }

  tags = {
    Name = "public-route-table-us-east-2"
  }
}

resource "aws_route_table_association" "public_rt_assoc_us_east_2a" {
  provider        = aws.us-east-2
  subnet_id       = aws_subnet.public_subnet_us_east_2a.id
  route_table_id  = aws_route_table.public_rt_us_east_2.id
}

resource "aws_security_group" "web_sg_us_east_2" {
  provider = aws.us-east-2
  vpc_id   = aws_vpc.norton_vpc_us_east_2.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg-us-east-2"
  }
}

resource "aws_iam_role" "ec2_role_us_east_2" {
  provider = aws.us-east-2
  name     = "ec2-role-us-east-2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy_us_east_2" {
  provider = aws.us-east-2
  name     = "ec2-policy-us-east-2"
  role     = aws_iam_role.ec2_role_us_east_2.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "ec2:Describe*",
      Effect   = "Allow",
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile_us_east_2" {
  provider = aws.us-east-2
  name     = "ec2-profile-us-east-2"
  role     = aws_iam_role.ec2_role_us_east_2.name
}
# EC2 Instances in us-east-2 Web server
resource "aws_instance" "web_instance_us_east_2a_1" {
  provider                 = aws.us-east-2
  ami                      = "ami-00db8dadb36c9815e" # Amazon Linux 2 AMI for us-east-2
  instance_type            = "t2.micro"
  subnet_id                = aws_subnet.public_subnet_us_east_2a.id
  vpc_security_group_ids   = [aws_security_group.web_sg_us_east_2.id]
  iam_instance_profile     = aws_iam_instance_profile.ec2_profile_us_east_2.name

  tags = {
    Name = "web-instance-us-east-2a-1"
  }
}
# EC2 Instances in us-east-2 Web server
resource "aws_instance" "web_instance_us_east_2a_2" {
  provider                 = aws.us-east-2
  ami                      = "ami-00db8dadb36c9815e" # Amazon Linux 2 AMI for us-east-2
  instance_type            = "t2.micro"
  subnet_id                = aws_subnet.public_subnet_us_east_2a.id
  vpc_security_group_ids   = [aws_security_group.web_sg_us_east_2.id]
  iam_instance_profile     = aws_iam_instance_profile.ec2_profile_us_east_2.name

  tags = {
    Name = "web-instance-us-east-2a-2"
  }
}

resource "aws_autoscaling_group" "web_asg_us_east_2a" {
  provider                 = aws.us-east-2
  desired_capacity         = 2
  max_size                 = 4
  min_size                 = 1
  vpc_zone_identifier      = [aws_subnet.public_subnet_us_east_2a.id] # us-east-2a
  launch_configuration     = aws_launch_configuration.web_lc_us_east_2a.id
  target_group_arns        = [aws_lb_target_group.web_tg_us_east_2.id]

  tag {
    key                    = "Name"
    value                  = "web-instance"
    propagate_at_launch    = true
  }
}

resource "aws_launch_configuration" "web_lc_us_east_2a" {
  provider                  = aws.us-east-2
  image_id                  = "ami-00db8dadb36c9815e" # Amazon Linux 2 AMI for us-east-2
  instance_type             = "t2.micro"
  security_groups           = [aws_security_group.web_sg_us_east_2.id]
  iam_instance_profile      = aws_iam_instance_profile.ec2_profile_us_east_2.name

  lifecycle {
    create_before_destroy   = true
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello World from $(hostname -f)" > /var/www/html/index.html
              EOF
}

resource "aws_lb_target_group" "web_tg_us_east_1" {
  provider = aws.us-east-1
  name     = "web-target-group-us-east-1"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.norton_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "web-target-group-us-east-1"
  }
}

resource "aws_lb_target_group" "web_tg_us_east_2" {
  provider = aws.us-east-2
  name     = "web-target-group-us-east-2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.norton_vpc_us_east_2.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "web-target-group-us-east-2"
  }
}
provider "aws" {
  alias  = "us-west-1"
  region = "us-west-1"
}
resource "aws_db_instance" "default" {
  provider = aws.us-east-1

  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  name                 = "mydatabase"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "my-rds-instance"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  provider = aws.us-east-1

  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]

  tags = {
    Name = "rds-subnet-group"
  }
}

resource "aws_security_group" "rds_sg" {
  provider = aws.us-east-1
  vpc_id   = aws_vpc.norton_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}
resource "aws_vpc" "norton_vpc_us_west_1" {
  provider   = aws.us-west-1
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "norton-vpc-us-west-1"
  }
}

resource "aws_subnet" "public_subnet_us_west_1a" {
  provider                  = aws.us-west-1
  vpc_id                    = aws_vpc.norton_vpc_us_west_1.id
  cidr_block                = "10.1.1.0/24"
  map_public_ip_on_launch   = true
  availability_zone         = "us-west-1a"
  tags = {
    Name = "public-subnet-us-west-1a"
  }
}

resource "aws_subnet" "public_subnet_us_west_1b" {
  provider                  = aws.us-west-1
  vpc_id                    = aws_vpc.norton_vpc_us_west_1.id
  cidr_block                = "10.1.2.0/24"
  map_public_ip_on_launch   = true
  availability_zone         = "us-west-1a"
  tags = {
    Name = "public-subnet-us-west-1b"
  }
}

resource "aws_subnet" "public_subnet_us_west_1c" {
  provider                  = aws.us-west-1
  vpc_id                    = aws_vpc.norton_vpc_us_west_1.id
  cidr_block                = "10.1.3.0/24"
  map_public_ip_on_launch   = true
  availability_zone         = "us-west-1c"
  tags = {
    Name = "public-subnet-us-west-1c"
  }
}

resource "aws_security_group" "rds_sg_us_west_1" {
  provider = aws.us-west-1
  vpc_id   = aws_vpc.norton_vpc_us_west_1.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg-us-west-1"
  }
}





# DB Subnet Group for RDS in us-west-1
resource "aws_db_subnet_group" "rds_subnet_group_us_west_1" {
  name       = "rds-subnet-group-us-west-1"
  subnet_ids = [
    aws_subnet.public_subnet_us_west_1a.id,
    aws_subnet.public_subnet_us_west_1c.id
  ]

  tags = {
    Name = "rds-subnet-group-us-west-1"
  }
}

resource "aws_db_instance" "read_replica" {
  replicate_source_db    = aws_db_instance.default.arn
  instance_class         = "db.t3.micro"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group_us_west_1.name
  vpc_security_group_ids = [aws_security_group.rds_sg_us_west_1.id]

  tags = {
    Name = "my-rds-instance-replica"
  }
}



provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

resource "aws_s3_bucket" "primary_backup_bucket" {
  provider = aws.eu-west-2
  bucket   = "primary-backup-bucket-eu"
 
}

resource "aws_s3_bucket_acl""primary_backup_bucket_acl" {
  provider = aws.eu-west-2
  bucket = aws_s3_bucket.primary_backup_bucket.bucket
  acl = "private"
}


resource "aws_s3_bucket" "secondary_backup_bucket" {
  provider = aws.us-west-1
  bucket   = "secondary-backup-bucket"

  tags = {
    Name = "secondary-backup-bucket"
  }
}

# Server-side encryption for the primary bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "primary_backup_encryption" {
  bucket = aws_s3_bucket.primary_backup_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# Server-side encryption for the secondary bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "secondary_backup_encryption" {
  bucket = aws_s3_bucket.secondary_backup_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}


# Versioning for the primary bucket
resource "aws_s3_bucket_versioning" "primary_backup_versioning" {
  bucket = aws_s3_bucket.primary_backup_bucket.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# # Versioning for the secondary bucket
# resource "aws_s3_bucket_versioning" "secondary_backup_versioning" {
#   bucket = aws_s3_bucket.secondary_backup_bucket.bucket

#   versioning_configuration {
#     status = "Enabled"
#   }
# }

# Cross-region replication configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.us-east-1
  role     = aws_iam_role.s3_replication_role.arn
  bucket   = aws_s3_bucket.primary_backup_bucket.bucket

  rule {
    id     = "replication-rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.secondary_backup_bucket.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
}

resource "aws_iam_role" "s3_replication_role" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "s3.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "s3_replication_policy" {
  name = "s3-replication-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.primary_backup_bucket.arn,
          "${aws_s3_bucket.primary_backup_bucket.arn}/*"
        ]
      },
      {
        Action   = "s3:ReplicateObject"
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.secondary_backup_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_replication_policy_attachment" {
  role       = aws_iam_role.s3_replication_role.name
  policy_arn = aws_iam_policy.s3_replication_policy.arn
}

# Enable automated RDS snapshot backups
resource "aws_rds_cluster" "norton_rds_cluster" {
  provider = aws.us-east-1
  cluster_identifier = "norton-rds-cluster"
  engine = "aurora-mysql"
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  master_username     = "admin"
  master_password     = "YourSecurePassword"
  # skip_final_snapshot = true  # Add this line to skip final snapshot for easy destroy and remove it if you want to keep the final snapshot
  skip_final_snapshot     = false
  final_snapshot_identifier = "11111"
}

# Snapshot copies to secondary region
resource "aws_db_cluster_snapshot" "norton_rds_snapshot" {
  provider = aws.us-east-1
  db_cluster_identifier = aws_rds_cluster.norton_rds_cluster.id
  db_cluster_snapshot_identifier = "norton-rds-snapshot"
}

resource "aws_s3_bucket_object" "rds_snapshot_backup" {
  provider = aws.us-west-1
  bucket = aws_s3_bucket.secondary_backup_bucket.bucket
  key    = "rds-backup/${aws_db_cluster_snapshot.norton_rds_snapshot.id}.snap" # It will be done once the backup is created

  source = aws_db_cluster_snapshot.norton_rds_snapshot.db_cluster_snapshot_identifier
}

# Create the IAM Developer Group
resource "aws_iam_group" "developer_group" {
  name = "developer-group"
}

# Attach EC2, RDS, S3, API Gateway, and CodePipeline policies to the group

# EC2 Policy
resource "aws_iam_group_policy" "developer_ec2_policy" {
  group = aws_iam_group.developer_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "ec2:Describe*",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ec2:TerminateInstances"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# RDS Policy
resource "aws_iam_group_policy" "developer_rds_policy" {
  group = aws_iam_group.developer_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "rds:Describe*",
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:ModifyDBInstance"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# S3 Policy
resource "aws_iam_group_policy" "developer_s3_policy" {
  group = aws_iam_group.developer_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

# API Gateway Policy
resource "aws_iam_group_policy" "developer_api_gateway_policy" {
  group = aws_iam_group.developer_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:DELETE",
          "apigateway:PUT"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_user" "developer2" {
  name = "developer2"
}


# CodePipeline Policy
resource "aws_iam_group_policy" "developer_codepipeline_policy" {
  group = aws_iam_group.developer_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "codepipeline:StartPipelineExecution",
          "codepipeline:GetPipelineState",
          "codepipeline:GetPipelineExecution",
          "codepipeline:ListPipelines"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
# Attach an existing IAM user to the developer group
resource "aws_iam_group_membership" "developer_group_membership" {
  name = "developer-group-membership"
  group = aws_iam_group.developer_group.name

  users = [
  #   "developer1",
  #   "developer2" # Add your original IAM user here
   ]
}
# Create API Gateway
resource "aws_api_gateway_rest_api" "developer_api" {
  name        = "DeveloperAPI"
  description = "API Gateway for Developer Group"
}

# Create API Gateway Resource (Example resource under the root)
resource "aws_api_gateway_resource" "developer_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.developer_api.id
  parent_id   = aws_api_gateway_rest_api.developer_api.root_resource_id
  path_part   = "developer-resource"
}

# Method for the resource
resource "aws_api_gateway_method" "developer_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.developer_api.id
  resource_id   = aws_api_gateway_resource.developer_api_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integration with a Lambda (or other backend, example placeholder)
resource "aws_api_gateway_integration" "developer_api_integration" {
  rest_api_id = aws_api_gateway_rest_api.developer_api.id
  resource_id = aws_api_gateway_resource.developer_api_resource.id
  http_method = aws_api_gateway_method.developer_api_method.http_method
  type        = "MOCK"
}
# S3 Bucket for CodePipeline Artifact Storage
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "developer-codepipeline-artifacts"
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

# CodePipeline definition
resource "aws_codepipeline" "developer_pipeline" {
  name     = "DeveloperPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        S3Bucket = aws_s3_bucket.codepipeline_bucket.bucket
        S3ObjectKey = "source.zip"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "CodeDeploy"
      version          = "1"
      input_artifacts  = ["source_output"]
      configuration = {
        ApplicationName = "MyApp"
        DeploymentGroupName = "MyDeploymentGroup"
      }
    }
  }
}

# Create the IAM Database Group
resource "aws_iam_group" "database_group" {
  name = "database-group"
}

# RDS Policy for the Database Group
resource "aws_iam_group_policy" "database_rds_policy" {
  group = aws_iam_group.database_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "rds:Describe*",
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:ModifyDBInstance",
          "rds:CreateDBSnapshot",
          "rds:DeleteDBSnapshot"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# S3 Policy for the Database Group
resource "aws_iam_group_policy" "database_s3_policy" {
  group = aws_iam_group.database_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::my-backup-bucket",   # Replace with your S3 bucket name
          "arn:aws:s3:::my-backup-bucket/*"  # Grant access to the bucket and its objects
        ]
      }
    ]
  })
}

# API Gateway Policy for the Database Group
resource "aws_iam_group_policy" "database_api_gateway_policy" {
  group = aws_iam_group.database_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:DELETE",
          "apigateway:PUT"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}
# Create KMS Key for encryption
resource "aws_kms_key" "backup_kms_key" {
  description = "KMS key for encrypting RDS and S3 backups"
}

# Create an AWS Backup Vault
resource "aws_backup_vault" "database_backup_vault" {
  name        = "database-backup-vault"
  kms_key_arn = aws_kms_key.backup_kms_key.arn

  tags = {
    Name = "DatabaseBackupVault"
  }
}

# Backup Plan for RDS and S3
resource "aws_backup_plan" "database_backup_plan" {
  name = "database-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.database_backup_vault.name
    schedule          = "cron(0 12 * * ? *)"  # Daily backup at 12 PM UTC
    lifecycle {
      delete_after = 30  # Retain backups for 30 days
    }
  }
}

# Backup selection for RDS
# resource "aws_backup_selection" "rds_backup_selection" {
#   name          = "rds-backup-selection"
#   iam_role_arn  = aws_iam_role.backup_role.arn
#   plan_id       = aws_backup_plan.database_backup_plan.id
#   resources = [
#     "arn:aws:rds:us-east-1:123456789012:db:my-rds-instance"                     # Replace with your actual RDS instance ARN
#   ]
# }

# Backup selection for S3
resource "aws_backup_selection" "s3_backup_selection" {
  name          = "s3-backup-selection"
  iam_role_arn  = aws_iam_role.backup_role.arn
  plan_id       = aws_backup_plan.database_backup_plan.id
  resources = [
    "arn:aws:s3:::my-backup-bucket"  # Replace with your S3 bucket ARN
  ]
}

# Create IAM Role for AWS Backup
resource "aws_iam_role" "backup_role" {
  name = "BackupServiceRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "backup.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach permissions to the Backup role for RDS and S3
resource "aws_iam_policy" "backup_policy" {
  name = "BackupPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots",
          "rds:DeleteDBSnapshot",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy_attach" {
  role       = aws_iam_role.backup_role.name
  policy_arn = aws_iam_policy.backup_policy.arn
}

# Create IAM Security IT Team Group
resource "aws_iam_group" "security_it_team_group" {
  name = "security-it-team-group"
}

# Permissions for the Security IT Team Group
resource "aws_iam_group_policy" "security_team_policy" {
  group = aws_iam_group.security_it_team_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "guardduty:*",
          "inspector:*",
          "cloudtrail:*",
          "macie2:*",
          "cloudwatch:*",
          "logs:*",
          "sns:*"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Create an SNS Topic for Notifications
resource "aws_sns_topic" "backup_notifications" {
  name = "backup-notifications"
}

# Create SNS Topic Subscription (Email) for IT Security Team
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = "securityteam@example.com"  # Replace with the actual email of the security team
}

# Allow SNS to be used by backup services
resource "aws_iam_role_policy_attachment" "sns_backup_policy_attach" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}
# Weekly Backup Plan for RDS and S3
resource "aws_backup_plan" "database_backup_plan_weekly" {
  name = "database-backup-plan-weekly"
  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.database_backup_vault.name
    schedule          = "cron(0 12 ? * 1 *)"  # Weekly backup every Monday at 12 PM UTC
    lifecycle {
      delete_after = 30  # Retain backups for 30 days
    }
  }
}

# SNS Notification for Backup Events
resource "aws_backup_vault_notifications" "vault_notifications" {
  backup_vault_name = aws_backup_vault.database_backup_vault.name
  sns_topic_arn     = aws_sns_topic.backup_notifications.arn
  backup_vault_events = ["BACKUP_JOB_COMPLETED", "BACKUP_JOB_FAILED"]
}

# Enable GuardDuty
resource "aws_guardduty_detector" "guardduty" {
  enable = true
}

# Enable AWS Inspector
# resource "aws_inspector_assessment_template" "inspector_template" {
#   name             = "inspector-template"
#   target_arn       = aws_inspector_assessment_target.example.arn
#   duration = 3600  # Duration of the assessment (1 hour)
#   rules_package_arns = ["arn:aws:inspector:us-east-1:123456789012:rulespackage/0-123abcde"]       # Replace with your actual rules package ARN and uncomment this resource
# }

resource "aws_inspector_assessment_target" "example" {
  name = "example-target"
}
# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "cloudtrail-logs-bucket"

}
# Enable CloudTrail
resource "aws_cloudtrail" "cloudtrail" {
  name                          = "security-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}




# # Enable Macie
# resource "aws_macie2_classification_job" "macie_job" {
#   name        = "sensitive-data-classification"
#   s3_job_definition {
#     bucket_definitions {
#       account_id   = "123456789012"  # Replace with your account ID
#       buckets      = [aws_s3_bucket.sensitive_data_bucket.id]
#     }
#   }
#   job_type = "ONE_TIME"
# }

# Enable CloudWatch Alarm for EC2 CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  alarm_name          = "high-cpu-utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alarm when CPU utilization exceeds 80%"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]
  dimensions = {
    InstanceId = "i-0123456789abcdef0"  # Replace with your EC2 instance ID
  }
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "app_log_group" {
  name              = "/aws/lambda/app-log-group"
  retention_in_days = 30
}

# Create CloudWatch Logs Metric Filter for Security Alarms
resource "aws_cloudwatch_log_metric_filter" "unauthorized_access_filter" {
  name                  = "unauthorized-access-filter"
  log_group_name        = aws_cloudwatch_log_group.app_log_group.name
  pattern               = "{ $.eventName = \"UnauthorizedAccess\" }"
  metric_transformation {
    name      = "UnauthorizedAccessCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

# CloudWatch Alarm for Unauthorized Access Metric
resource "aws_cloudwatch_metric_alarm" "unauthorized_access_alarm" {
  alarm_name          = "unauthorized-access-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAccessCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Triggers when there is unauthorized access detected"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]
}

# Create an SNS Topic for Security Notifications
resource "aws_sns_topic" "security_notifications" {
  name = "security-notifications"
}

# Create SNS Topic Subscription for Email (Security IT Team)
resource "aws_sns_topic_subscription" "email_subscription_security_team" {
  topic_arn = aws_sns_topic.security_notifications.arn
  protocol  = "email"
  endpoint  = "securityteam@example.com"  # Replace with the actual email
}



# Create CloudWatch Event Rule for GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings_rule" {
  name        = "guardduty-findings-rule"
  description = "Capture GuardDuty findings"
  event_pattern = jsonencode({
    "source": [
      "aws.guardduty"
    ],
    "detail-type": [
      "GuardDuty Finding"
    ]
  })
}

# SNS Target for GuardDuty findings
resource "aws_cloudwatch_event_target" "guardduty_findings_target" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings_rule.name
  arn       = aws_sns_topic.security_notifications.arn
}



# Enable Inspector
resource "aws_inspector_assessment_target" "inspector_target" {
  name = "inspector-assessment-target"
}

# Rename the duplicate AWS Inspector resource
# resource "aws_inspector_assessment_template" "inspector_template_security" {
#   name             = "inspector-template-security"
#   target_arn       = aws_inspector_assessment_target.example.arn
#   duration         = 3600
#   rules_package_arns = ["arn:aws:inspector:us-east-1:123456789012:rulespackage/0-123abcde"]          # Replace with your actual rules package ARN and uncomment this resource
# }


# SNS Target for Inspector Findings
resource "aws_cloudwatch_event_rule" "inspector_rule" {
  name        = "inspector-findings-rule"
  description = "Send Inspector findings to SNS"
  event_pattern = jsonencode({
    "source": [
      "aws.inspector"
    ],
    "detail-type": [
      "Inspector Assessment Run State Change"
    ]
  })
}

resource "aws_cloudwatch_event_target" "inspector_findings_target" {
  rule = aws_cloudwatch_event_rule.inspector_rule.name
  arn  = aws_sns_topic.security_notifications.arn
}

# Enable CloudTrail
# Rename the duplicate CloudTrail resource
resource "aws_cloudtrail" "cloudtrail_security" {
  name                          = "security-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}


# SNS Target for CloudTrail Events
resource "aws_cloudwatch_event_rule" "cloudtrail_rule" {
  name        = "cloudtrail-events-rule"
  description = "Notify when critical CloudTrail events occur"
  event_pattern = jsonencode({
    "source": [
      "aws.cloudtrail"
    ],
    "detail-type": [
      "AWS API Call via CloudTrail"
    ],
    "detail": {
      "eventName": [
        "ConsoleLogin",
        "UnauthorizedAccess"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "cloudtrail_target" {
  rule = aws_cloudwatch_event_rule.cloudtrail_rule.name
  arn  = aws_sns_topic.security_notifications.arn
}
# # Macie Job for S3 Sensitive Data Discovery
# resource "aws_macie2_classification_job" "macie_job_security" {
#   name        = "sensitive-data-classification-security"
#   s3_job_definition {
#     bucket_definitions {
#       account_id   = "123456789012"  # Replace with your account ID
#       buckets      = [aws_s3_bucket.sensitive_data_bucket.id]
#     }
#   }
#   job_type = "ONE_TIME"
# }


# SNS Target for Macie Findings
resource "aws_cloudwatch_event_rule" "macie_rule" {
  name        = "macie-findings-rule"
  description = "Send Macie findings to SNS"
  event_pattern = jsonencode({
    "source": [
      "aws.macie"
    ],
    "detail-type": [
      "Macie Finding"
    ]
  })
}

resource "aws_cloudwatch_event_target" "macie_target" {
  rule = aws_cloudwatch_event_rule.macie_rule.name
  arn  = aws_sns_topic.security_notifications.arn
}
# CloudWatch Alarm for EC2 CPU Utilization
# Rename the duplicate CloudWatch metric alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm_security" {
  alarm_name          = "high-cpu-utilization-security"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_actions       = [aws_sns_topic.security_notifications.arn]
}

# Rename the duplicate CloudWatch metric alarm for unauthorized access
resource "aws_cloudwatch_metric_alarm" "unauthorized_access_alarm_security" {
  alarm_name          = "unauthorized-access-alarm-security"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAccessCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.security_notifications.arn]
}

# Create a Route 53 Hosted Zone
resource "aws_route53_zone" "secure_zone" {
  name = "norton.com"  # Replace with your domain name
}

# # Enable DNSSEC Signing
# resource "aws_route53_dnssec" "secure_dnssec" {
#   hosted_zone_id = aws_route53_zone.secure_zone.id
# }

# # Create a DNSSEC Key Signing Key (KSK)
# resource "aws_kms_key" "dnssec_ksk" {
#   description = "Key Signing Key for DNSSEC"
# } not supported in Terraform


# Create a Firewall Manager Admin Account
# resource "aws_organizations_organization" "organization" {        # Uncomment this block if you are using AWS Organizations and enable the firewall manager
#   feature_set = "ALL"
# }

# resource "aws_fms_admin_account" "firewall_admin" {
#   account_id = "123456789012"  # Replace with the firewall manager admin account ID
# }

# Attach Policy to Security IT Team Group for Firewall Management
# resource "aws_iam_group_policy" "firewall_policy" {
#   group = aws_iam_group.security_it_team_group.name

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = [
#           "fms:*",       # Full access to Firewall Manager
#           "wafv2:*",     # Access to Web Application Firewall (WAF)
#           "ec2:Describe*",  # Access to describe network settings
#         ],
#         Effect = "Allow",
#         Resource = "*"
#       }
#     ]
#   })
# }
# Create Route 53 Hosted Zone (if not already created in DNSSEC)
resource "aws_route53_zone" "main_zone" {
  name = "nortonhealth.com"  # Replace with your domain name
}

# Declare the API Gateway Rest API
resource "aws_api_gateway_rest_api" "example_api" {
  name        = "example-api"
  description = "Dummy API Gateway for testing"
}

# Create an API resource (a path like /dummy)
resource "aws_api_gateway_resource" "example_resource" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  parent_id   = aws_api_gateway_rest_api.example_api.root_resource_id
  path_part   = "dummy"  # This creates /dummy in the API path
}

# Define the GET method for the /dummy resource
resource "aws_api_gateway_method" "example_method" {
  rest_api_id   = aws_api_gateway_rest_api.example_api.id
  resource_id   = aws_api_gateway_resource.example_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integration for the GET method
resource "aws_api_gateway_integration" "example_integration" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  resource_id = aws_api_gateway_resource.example_resource.id
  http_method = aws_api_gateway_method.example_method.http_method
  type        = "MOCK"  # Using a mock integration as a dummy response
}

# Method Response for GET /dummy
resource "aws_api_gateway_method_response" "example_method_response" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  resource_id = aws_api_gateway_resource.example_resource.id
  http_method = aws_api_gateway_method.example_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration Response for GET /dummy
resource "aws_api_gateway_integration_response" "example_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  resource_id = aws_api_gateway_resource.example_resource.id
  http_method = aws_api_gateway_method.example_method.http_method
  status_code = aws_api_gateway_method_response.example_method_response.status_code
}

# API Gateway Deployment (Required for invoking the API)
resource "aws_api_gateway_deployment" "example_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.example_integration
  ]  # Ensure the API integration is created first

  rest_api_id = aws_api_gateway_rest_api.example_api.id
  stage_name  = "prod"  # Define the stage for deployment
}


# Fix the Route 53 Record referencing the API Gateway
# resource "aws_route53_record" "api_gateway_record" {
#   zone_id = aws_route53_zone.main_zone.id
#   name    = "api.norton.com"  # Subdomain for the API Gateway
#   type    = "A"

#   alias {
#     name                   = aws_api_gateway_deployment.example_api_deployment.invoke_url  # Fix the reference with actual encryption id
#     zone_id                = aws_api_gateway_rest_api.example_api.id  # Fix the zone reference with actual API ID
#     evaluate_target_health = true
#   }
# }

# Fix the CloudFront Distribution referencing the API Gateway
# resource "aws_cloudfront_distribution" "api_gw_distribution" {
#   origin {
#     domain_name = aws_api_gateway_deployment.example_api_deployment.invoke_url  # Fix the reference
#     origin_id   = "api-gateway-origin"
#   }

#   enabled             = true
#   is_ipv6_enabled     = true
#   default_root_object = "index.html"

#   default_cache_behavior {
#     target_origin_id       = "api-gateway-origin"
#     viewer_protocol_policy = "redirect-to-https"

#     allowed_methods = ["GET", "HEAD", "OPTIONS"]
#     cached_methods  = ["GET", "HEAD"]
#     forwarded_values {
#       query_string = false
#       cookies {
#         forward = "none"
#       }
#     }
#   }

#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }

#   viewer_certificate {
#     cloudfront_default_certificate = true
#   }
# }

# Route 53 Alias record to CloudFront
# resource "aws_route53_record" "cloudfront_alias" {
#   zone_id = aws_route53_zone.main_zone.id
#   name    = "cdn.example.com"  # Subdomain for CloudFront
#   type    = "A"

#   alias {
#     name                   = aws_cloudfront_distribution.api_gw_distribution.domain_name        # Fix the reference with actual CloudFront distribution domain name
#     zone_id                = aws_cloudfront_distribution.api_gw_distribution.hosted_zone_id     # Fix the reference with actual CloudFront distribution hosted zone ID
#     evaluate_target_health = false
#   }
# }
# API Gateway Setup (Already created, adding security permissions)

# Attach API Gateway Access for IT Security Team
resource "aws_iam_group_policy" "api_gateway_policy" {
  group = aws_iam_group.security_it_team_group.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "apigateway:*"  # Full access to API Gateway
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}



# SNS Integration for Route 53 Changes
resource "aws_cloudwatch_event_rule" "route53_changes_rule" {
  name        = "route53-changes-rule"
  description = "Notify on Route 53 changes"
  event_pattern = jsonencode({
    "source": [
      "aws.route53"
    ],
    "detail-type": [
      "AWS API Call via CloudTrail"
    ]
  })
}

resource "aws_cloudwatch_event_target" "route53_changes_sns_target" {
  rule = aws_cloudwatch_event_rule.route53_changes_rule.name
  arn  = aws_sns_topic.security_notifications.arn
}
