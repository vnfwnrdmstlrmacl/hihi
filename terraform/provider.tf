terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = ">= 0.13.0"
    }
  }
}

# AWS Provider 설정
provider "aws" {
  region = var.aws_region # variables.tf에 정의된 리전 사용
}

# Tailscale Provider 설정
# Ansible이 생성한 vault.yml의 api_key와 tailnet을 변수로 받아 처리합니다.
provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailnet
}
