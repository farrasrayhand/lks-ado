variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "kaltim-smart-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_private_subnet_cidrs" {
  description = "App private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_private_subnet_cidrs" {
  description = "Database private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "kaltim_smart_platform"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "kaltim_admin"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "app_port" {
  description = "Application port"
  type        = number
  default     = 80
}

variable "app_key" {
  description = "Laravel APP_KEY"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name for file uploads"
  type        = string
  default     = "kaltim-smart-platform-uploads"
}

variable "github_repo_url" {
  description = "GitHub repository URL to clone on EC2"
  type        = string
}

variable "app_ami_id" {
  description = "AMI ID for EC2 instances — gunakan AMI default saat pertama deploy, ganti dengan custom AMI setelah setup selesai"
  type        = string
  default     = "ami-0c802847a7dd848c0"
}

variable "lex_bot_alias_id" {
  description = "Lex Bot Alias ID — isi setelah membuat alias di AWS Console (Section 5)"
  type        = string
  default     = ""
}
