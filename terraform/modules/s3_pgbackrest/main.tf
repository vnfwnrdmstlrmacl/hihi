# 1. S3 버킷 생성
resource "aws_s3_bucket" "pg_backup" {
  bucket = "${var.project_name}-pgbackrest-repo"

  # 실수로 인한 삭제 방지 (운영 환경 권장)
  # force_destroy = false 
}

# 2. 버킷 버전 관리 (실수 대비)
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.pg_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. 모든 퍼블릭 액세스 차단 (필수 보안)
resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.pg_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 4. 서버 측 암호화 설정
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.pg_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 5. pgBackRest 전용 IAM 유저 생성
resource "aws_iam_user" "pgbackrest" {
  name = "${var.project_name}-pgbackrest-user"
}

# 6. IAM 유저 전용 Access Key 생성 (Ansible vars.yml에 들어갈 값)
resource "aws_iam_access_key" "pgbackrest" {
  user = aws_iam_user.pgbackrest.name
}

# 7. S3 접근 권한 정책 정의
resource "aws_iam_policy" "pgbackrest_s3_policy" {
  name        = "${var.project_name}-s3-policy"
  description = "Allow pgBackRest to manage backups in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Effect   = "Allow"
        Resource = [
          "${aws_s3_bucket.pg_backup.arn}",
          "${aws_s3_bucket.pg_backup.arn}/*"
        ]
      }
    ]
  })
}

# 8. 유저에 정책 연결
resource "aws_iam_user_policy_attachment" "attach" {
  user       = aws_iam_user.pgbackrest.name
  policy_arn = aws_iam_policy.pgbackrest_s3_policy.arn
}
resource "aws_s3_bucket" "pgbackrest_repo" {
  bucket        = "test-pgbackrest-repo"
  force_destroy = true  # 추가
}
