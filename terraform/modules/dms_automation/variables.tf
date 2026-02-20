variable "forward_task_arn" {
  type = string
}

variable "reverse_task_arn" {
  type = string
}

variable "project_name" {
  type    = string
}
variable "onprem_host" {
  description = "복구 체크를 위한 온프레미스 DB IP"
  type        = string
}
