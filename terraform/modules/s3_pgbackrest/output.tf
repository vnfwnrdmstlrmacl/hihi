output "bucket_name" {
  value = aws_s3_bucket.pg_backup.id
}

output "iam_access_key_id" {
  value = aws_iam_access_key.pgbackrest.id
}

output "iam_secret_access_key" {
  value     = aws_iam_access_key.pgbackrest.secret
  sensitive = true
}
