resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# 2. RDS 보안 그룹 (VPC 내부 및 브릿지 통신 허용)
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow DB traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # VPC 내부 대역(Tailscale 브릿지 포함)에서의 접속 허용
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.dms_sg_id] # DMS 모듈에서 넘어온 SG ID
  }
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.bridge_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. 파라미터 그룹 (DMS 및 성능 최적화 설정)
resource "aws_db_parameter_group" "pg13" {
  name   = "${var.project_name}-pg13-params"
  family = "postgres13"

  # DMS CDC(Change Data Capture)를 위한 설정
  parameter {
    name  = "rds.logical_replication"
    value = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_sender_timeout"
    value = "0"
  }
}


# 4. RDS PostgreSQL 인스턴스
resource "aws_db_instance" "rds" {
  identifier           = "${var.project_name}-rds"
  allocated_storage    = var.db_allocated_storage
  engine               = "postgres"
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  
  db_name              = "appdb"
  username             = "postgres"
  password             = var.db_password
  
  # ✅ 스토리지: 최소/최대 분리해서 자동확장 켜기
  allocated_storage     = var.db_allocated_storage   # 예: 100 (최소 시작)
  max_allocated_storage = var.db_max_allocated_storage # 예: 300 (자동 확장 상한)
  storage_type = "gp3"

  # 운영 안정성 (다운타임 최소화/작업 시간 확보)
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  publicly_accessible     = false

  parameter_group_name = aws_db_parameter_group.pg13.name

  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  skip_final_snapshot  = false # 연습/테스트용 (실운영시 false 권장)
  publicly_accessible  = false # 외부 노출 차단
  apply_immediately = true

  tags = { Name = "${var.project_name}-rds" }

}
