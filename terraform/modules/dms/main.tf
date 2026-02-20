# 1. DMS 복제 인스턴스 보안 그룹
resource "aws_security_group" "dms_sg" {
  name        = "${var.project_name}-dms-sg"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-dms-sg" }
}

# 2. DMS 서브넷 그룹
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_description = "DMS subnet group"
  replication_subnet_group_id          = "${var.project_name}-dms-subnet-group"
  subnet_ids                           = var.subnet_ids
}

# 3. DMS 복제 인스턴스 생성
resource "aws_dms_replication_instance" "main" {
  replication_instance_class   = var.dms_instance_class
  replication_instance_id      = "${var.project_name}-reproduction-instance"
  replication_subnet_group_id  = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids       = [aws_security_group.dms_sg.id]
  multi_az                     = false
  apply_immediately            = true
}

# 4. 소스 엔드포인트 (온프레미스 PostgreSQL)
resource "aws_dms_endpoint" "source" {
  endpoint_id                 = "onprem-source"
  endpoint_type               = "source"
  engine_name                 = "postgres"
  server_name                 = var.onprem_db_tailscale_ip # 온프레미스 Tailscale IP 사용
  port                        = 5432
  database_name               = "appdb"
  username                    = "postgres"
  password                    = var.db_password
  ssl_mode                    = "none"
}

# 5. 타겟 엔드포인트 (AWS RDS)
resource "aws_dms_endpoint" "target" {
  endpoint_id                 = "rds-target"
  endpoint_type               = "target"
  engine_name                 = "postgres"
  server_name                 = var.rds_endpoint
  port                        = 5432
  database_name               = "appdb"
  username                    = "postgres"
  password                    = var.db_password
  ssl_mode                    = "none"
}

# 6. [신규 추가] DMS 복제 태스크
resource "aws_dms_replication_task" "main" {
  migration_type           = "full-load"
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  replication_task_id      = "${var.project_name}-migration-task"
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn

  # 소스(온프레)의 모든 테이블을 포함하는 매핑 설정
  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection", rule-id = "1", rule-name = "include_api",
        object-locator = { schema-name = "api", table-name = "%" },
        rule-action = "include"
      },
      {
        rule-type = "selection", rule-id = "2", rule-name = "include_app",
        object-locator = { schema-name = "app", table-name = "%" },
        rule-action = "include"
      }
    ]
  })
  replication_task_settings = jsonencode({
    TargetMetadata = {
      TargetTablePrepMode = "DROP_AND_CREATE" # 테이블 자동 생성 및 초기화
      SupportLobs          = true
      FullLobMode          = false
      LobChunkSize         = 64
    }
    Logging = {
      EnableLogging = true # CloudWatch 로그 활성화
    }
  })

  tags = { Name = "${var.project_name}-migration-task" }
}
# 7. [역방향] 소스 엔드포인트 (AWS RDS가 이번엔 출발지)
resource "aws_dms_endpoint" "reverse_source" {
  endpoint_id   = "rds-source-rev"
  endpoint_type = "source"
  engine_name   = "postgres"
  server_name   = var.rds_endpoint
  port          = 5432
  database_name = "appdb"
  username      = "postgres"
  password      = var.db_password
  ssl_mode      = "none" # 필요시 'require'로 변경
}

# 8. [역방향] 타겟 엔드포인트 (온프레미스가 이번엔 목적지)
resource "aws_dms_endpoint" "reverse_target" {
  endpoint_id   = "onprem-target-rev"
  endpoint_type = "target"
  engine_name   = "postgres"
  server_name   = var.onprem_db_tailscale_ip
  port          = 5432
  database_name = "appdb"
  username      = "postgres"
  password      = var.db_password
  ssl_mode      = "none"
}

# 9. [역방향] DMS 복제 태스크 (Failback용 CDC)
resource "aws_dms_replication_task" "reverse" {
  migration_type           = "cdc" # 중요: 데이터 덮어쓰지 않고 변경분만 전송
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  replication_task_id      = "${var.project_name}-reverse-task"
  source_endpoint_arn      = aws_dms_endpoint.reverse_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.reverse_target.endpoint_arn

  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection", rule-id = "1", rule-name = "include_api",
        object-locator = { schema-name = "api", table-name = "%" },
        rule-action = "include"
      },
      {
        rule-type = "selection", rule-id = "2", rule-name = "include_app",
        object-locator = { schema-name = "app", table-name = "%" },
        rule-action = "include"
      }
    ]
  })

  replication_task_settings = jsonencode({
    TargetMetadata = {
      # 중요: 역방향은 이미 데이터가 있는 상태이므로 테이블을 절대 건드리지 않음
      TargetTablePrepMode = "DO_NOTHING"
      SupportLobs         = true
    }
    Logging = {
      EnableLogging = true
    }
  })

  tags = { Name = "${var.project_name}-reverse-task" }
}
