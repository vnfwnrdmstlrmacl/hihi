# 1. Tailscale 관련 (에러 방지를 위해 이름 통일!)
variable "tailscale_api_key" {
  type      = string
  sensitive = true
}

# 중요: provider.tf에서 var.tailnet을 쓰고 있다면 이름을 tailnet으로 맞춰야 함
variable "tailnet" {
  type    = string
  default = "zmsdlfsktek24@gmail.com"
}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

variable "onprem_db_tailscale_ip" {
  type = string
}

# 2. AWS 관련 (default 값이 이미 있어서 콘솔 안 봐도 됨)
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "pg-hybrid-migration"
}

variable "vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

# 3. RDS/DMS 관련
variable "postgres_version" {
  type    = string
  default = "13.23"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_allocated_storage" {
  type    = number
  default = 50
}

variable "bridge_ami_id" {
  type    = string
  default = "ami-0dec6548c7c0d0a96"
}

variable "bridge_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "dms_instance_class" {
  type    = string
  default = "dms.t3.medium"
}

variable "s3_retention_days" {
  type    = number
  default = 30
}
