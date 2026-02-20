output "rds_endpoint" {
  value = module.rds.db_instance_address
}

output "s3_bucket_name" {
  value = module.s3_pgbackrest.bucket_name
}

output "tailscale_bridge_public_ip" {
  value = module.tailscale_bridge.public_ip
  description = "Tailscale Bridge EC2의 공인 IP (관리용)"
}

output "ansible_vars_path" {
  value = local_file.ansible_vars.filename
}
