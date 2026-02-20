output "replication_instance_arn" {
  value = aws_dms_replication_instance.main.replication_instance_arn
}
# Ansible pg_hba.yml에서 사용할 서브넷 대역 정보
output "dms_instance_private_ip" {
  value = aws_dms_replication_instance.main.replication_instance_private_ips[0]
}

# 복제 인스턴스가 속한 VPC의 CIDR (이걸 Ansible 변수로 쓰면 IP가 바뀌어도 됨)
output "dms_vpc_cidr" {
  value = var.vpc_cidr # 부모 모듈에서 넘겨받는 vpc_cidr가 있다면 활용
}
# [추가] DMS 보안 그룹 ID - RDS와 Bridge SG 설정에서 참조할 때 사용
output "dms_sg_id" {
  value = aws_security_group.dms_sg.id
}
# 기존 코드 아래에 추가
output "forward_task_arn" {
  value = aws_dms_replication_task.main.replication_task_arn
}

output "reverse_task_arn" {
  value = aws_dms_replication_task.reverse.replication_task_arn
}
