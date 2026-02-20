#################################################
# 1. Tailscale 설정
#################################################
resource "tailscale_tailnet_key" "bridge_key" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 3600
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
# 3. 백업 저장소 (S3 & IAM) - 이름 충돌 방지 추가
#################################################
module "s3_pgbackrest" {
  source       = "./modules/s3_pgbackrest"
  # 아래처럼 project_name을 조합해서 쓰도록 모듈 내부가 되어있어야 합니다.
  project_name = "${var.project_name}-repo-v2" 
}

#################################################
# 4. 마이그레이션 엔진 (DMS) - SG ID 생성을 위해 위로 이동
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
  vpc_cidr               = var.vpc_cidr
}

#################################################
# 5. VPN 게이트웨이 & 6. RDS (DMS SG 참조)
#################################################
module "tailscale_bridge" {
  source             = "./modules/tailscale_bridge"
  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnets[0]
  vpc_cidr           = module.vpc.vpc_cidr
  ami_id             = var.bridge_ami_id
  instance_type      = var.bridge_instance_type
  dms_sg_id          = module.dms.dms_sg_id # dms 모듈에서 출력된 ID 사용
  tailscale_auth_key = tailscale_tailnet_key.bridge_key.key
}

module "rds" {
  source               = "./modules/rds"
  project_name         = var.project_name
  vpc_id               = module.vpc.vpc_id
  db_subnet_ids        = module.vpc.private_subnets
  vpc_cidr             = var.vpc_cidr
  instance_class       = var.db_instance_class
  engine_version       = var.postgres_version
  db_password          = var.db_password
  db_allocated_storage = var.db_allocated_storage
  dms_sg_id            = module.dms.dms_sg_id
  bridge_sg_id         = module.tailscale_bridge.bridge_sg_id
}

#################################################
# 7. Failover 자동화 (DMS 태스크 ARN 참조)
#################################################
module "dms_auto_failover" {
  source           = "./modules/dms_automation"
  forward_task_arn = module.dms.forward_task_arn
  reverse_task_arn = module.dms.reverse_task_arn
  onprem_host      = var.onprem_db_tailscale_ip
  project_name     = var.project_name
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

