# modules/tailscale_bridge/outputs.tf
output "bridge_sg_id" {
  description = "The security group ID of the Tailscale bridge instance"
  value       = aws_security_group.ts_bridge_sg.id
}
output "bridge_interface_id" {
  value = aws_instance.bridge.primary_network_interface_id
}

output "private_ip" {
  description = "Tailscale Bridge EC2의 사설 IP"
  # grep 결과에 따라 .bridge 로 수정했습니다.
  value       = aws_instance.bridge.private_ip
}

output "public_ip" {
  description = "Tailscale Bridge EC2의 공인 IP"
  value       = aws_instance.bridge.public_ip
}

output "instance_id" {
  description = "Tailscale Bridge EC2의 인스턴스 ID"
  value       = aws_instance.bridge.id
}
