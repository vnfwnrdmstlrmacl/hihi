# 1. Tailscale Bridge 전용 보안 그룹
resource "aws_security_group" "ts_bridge_sg" {
  name        = "${var.project_name}-ts-bridge-sg"
  description = "Security group for Tailscale VPN Bridge"
  vpc_id      = var.vpc_id

  # 아웃바운드: 모든 곳으로 나가는 트래픽 허용 (Tailscale 통신 필수)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 인바운드: VPC 내부(RDS, DMS)에서 오는 트래픽을 온프레로 넘겨주기 위해 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [var.dms_sg_id]
  }
  tags = {
    Name = "${var.project_name}-ts-bridge-sg"
  }
}

# 2. Tailscale Bridge EC2 인스턴스
resource "aws_instance" "bridge" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ts_bridge_sg.id]
  
  # [핵심] 다른 곳에서 온 패키지를 전달해야 하므로 소스/대상 확인을 끕니다.
  source_dest_check = false

  # 인스턴스 초기 설정 스크립트
  user_data = <<-EOF
              #!/bin/bash
              # 커널 레벨 IP 포워딩 활성화 (AL2023/CentOS 계열 필수 설정)
              echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
              echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
              sudo sysctl -p

              # Tailscale 설치
              curl -fsSL https://tailscale.com/install.sh | sh

              # Tailscale 실행 및 라우팅 광고
              # --advertise-routes: 온프레미스 서버가 이 VPC 대역을 찾아오게 하는 경로 설정
              sudo tailscale up --authkey=${var.tailscale_auth_key} --advertise-routes=${var.vpc_cidr} --accept-dns=false
              sudo iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE

              EOF

  tags = {
    Name = "${var.project_name}-ts-bridge"
  }
}
