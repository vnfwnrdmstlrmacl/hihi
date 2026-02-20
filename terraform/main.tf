#################################################
# 1. Tailscale 설정 (키 생성 자동화)
#################################################
# 테라폼이 직접 Tailscale 콘솔에 접속해 일회용 키를 만듭니다.
resource "tailscale_tailnet_key" "bridge_key" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 3600 # 1시간 유효
}

#################################################
# 2. 네트워크 인프라 (VPC)
#################################################
module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

#################################################
# 3. 백업 저장소 (S3 & IAM)
#################################################
module "s3_pgbackrest" {
  source       = "./modules/s3_pgbackrest"
  project_name = var.project_name
}

#################################################
# 4. VPN 게이트웨이 (Tailscale Bridge)
#################################################
module "tailscale_bridge" {
  source             = "./modules/tailscale_bridge"
  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnets[0]
  vpc_cidr           = module.vpc.vpc_cidr
  ami_id             = var.bridge_ami_id
  instance_type      = var.bridge_instance_type
  # [핵심] 위에서 자동 생성한 Tailscale 키를 전달
  dms_sg_id          = module.dms.dms_sg_id
  tailscale_auth_key = tailscale_tailnet_key.bridge_key.key
}

#################################################
# 5. 타겟 데이터베이스 (RDS)
#################################################
module "rds" {
  source               = "./modules/rds"
  project_name         = var.project_name
  vpc_id               = module.vpc.vpc_id
  db_subnet_ids        = module.vpc.private_subnets
  vpc_cidr             = module.vpc.vpc_cidr
  instance_class       = var.db_instance_class
  engine_version       = var.postgres_version
  db_password          = var.db_password
  db_allocated_storage = var.db_allocated_storage
  dms_sg_id             = module.dms.dms_sg_id
  bridge_sg_id = module.tailscale_bridge.bridge_sg_id
}

#################################################
# 6. 마이그레이션 엔진 (DMS)
#################################################
module "dms" {
  source                 = "./modules/dms"
  project_name           = var.project_name
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnets
  onprem_db_tailscale_ip = var.onprem_db_tailscale_ip
  rds_endpoint           = module.rds.db_instance_address
  db_password            = var.db_password
  dms_instance_class     = var.dms_instance_class
  vpc_cidr = var.vpc_cidr
}

#################################################
# 7. Ansible 변수 자동 생성 (Local File)
#################################################
# 모든 인프라 생성이 끝나면 Ansible이 읽을 수 있는 vars.yml을 만듭니다.
resource "local_file" "ansible_vars" {
  content  = <<-EOT
    # Terraform Generated Variables
    # Generated at: ${timestamp()}

    # S3 Backup
    s3_bucket_name: "${module.s3_pgbackrest.bucket_name}"
    s3_region: "${var.aws_region}"
    aws_access_key: "${module.s3_pgbackrest.iam_access_key_id}"
    aws_secret_key: "${module.s3_pgbackrest.iam_secret_access_key}"

    # RDS & Migration
    rds_endpoint: "${module.rds.db_instance_address}"
    db_password: "${var.db_password}"
    postgres_version: "${var.postgres_version}"

    # Connectivity
    vpc_cidr: "${var.vpc_cidr}"
    bridge_private_ip: "${module.tailscale_bridge.private_ip}"
    onprem_ip: "${var.onprem_db_tailscale_ip}"
    tailscale_auth_key: "${tailscale_tailnet_key.bridge_key.key}"
  EOT
  filename = "${path.module}/../db/group_vars/backup/terraform.yml"
  # 모든 리소스가 다 만들어진 후 파일을 생성하도록 강제함
  depends_on = [
    module.s3_pgbackrest,
    module.rds,
    module.tailscale_bridge
  ]
}
#################################################
# 8. 네트워크 경로 연결 (VPC -> Bridge -> On-Prem)
#################################################
# VPC 모듈과 Bridge 모듈이 모두 생성된 후, 실제 라우팅 규칙을 꽂아줍니다.
resource "aws_route" "private_to_onprem" {
  route_table_id         = module.vpc.private_route_table_id
  destination_cidr_block = "100.64.0.0/10" # Tailscale 대역
  network_interface_id   = module.tailscale_bridge.bridge_interface_id
}

module "dms_auto_failover" {
  source = "./modules/dms_automation"

  # 기존 DMS 리소스의 ARN을 결과값으로 넣어줌
  forward_task_arn = aws_dms_replication_task.forward.replication_task_arn
  reverse_task_arn = aws_dms_replication_task.reverse.replication_task_arn
}
