variable "dms_sg_id" {
  description = "The security group ID of the DMS replication instance"
  type        = string
}
variable "project_name" {
  description = "프로젝트 이름 접두어"
  type        = string
}

variable "vpc_id" {
  description = "브릿지가 속할 VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "브릿지가 위치할 Public 서브넷 ID"
  type        = string
}

variable "vpc_cidr" {
  description = "온프레미스에 홍보할 AWS 네트워크 대역"
  type        = string
}

variable "ami_id" {
  description = "EC2에 사용할 AMI ID (예: Amazon Linux 2023)"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 사양"
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale 인증 키"
  type        = string
  sensitive   = true
}
