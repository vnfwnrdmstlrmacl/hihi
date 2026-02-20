variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_ids" {
  description = "RDS가 위치할 Private 서브넷 리스트"
  type        = list(string)
}

variable "instance_class" {
  description = "RDS 인스턴스 사양 (예: db.t3.micro)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL 버전 (예: 13.12)"
  type        = string
}

variable "db_password" {
  description = "데이터베이스 마스터 암호"
  type        = string
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "할당 용량 (GB)"
  type        = number
}

variable "vpc_cidr" {
  description = "접속 허용을 위한 VPC 대역"
  type        = string
}
variable "dms_sg_id" {
  description = "The security group ID of the DMS replication instance"
  type        = string
}
variable "bridge_sg_id" {
  description = "The security group ID of the Tailscale bridge"
  type        = string
}
