# [1] IAM Role & Policy (동일)
resource "aws_iam_role" "dms_lambda_role" {
  name = "${var.project_name}-dms-automation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "dms_lambda_policy" {
  role = aws_iam_role.dms_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = ["dms:*", "logs:*"], Effect = "Allow", Resource = "*" }]
  })
}

# [2] Lambda 함수 (동일)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "dms_automation" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-dms-failover-failback"
  role             = aws_iam_role.dms_lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      FORWARD_TASK_ARN = var.forward_task_arn
      REVERSE_TASK_ARN = var.reverse_task_arn
      ON_PREM_HOST     = var.onprem_host
    }
  }
}

# [3] 규칙 1: 정방향 장애 시 즉시 실행
resource "aws_cloudwatch_event_rule" "dms_fail_rule" {
  name = "${var.project_name}-failover-rule"
  event_pattern = jsonencode({
    "source": ["aws.dms"],
    "detail-type": ["DMS Replication Task State Change"],
  #  "detail": {
  #    "status": ["failed", "stopped"]
  #  }
  })
}

# [4] 규칙 2: 온프레미스 복구 체크 (5분 주기)
resource "aws_cloudwatch_event_rule" "onprem_check_rule" {
  name                = "${var.project_name}-failback-check"
  schedule_expression = "rate(1 minute)"
}

# [5] 타겟 연결 (수정됨: 세미콜론 제거 및 줄바꿈 적용)
resource "aws_cloudwatch_event_target" "target_fail" { 
  rule = aws_cloudwatch_event_rule.dms_fail_rule.name
  arn  = aws_lambda_function.dms_automation.arn 
}

resource "aws_cloudwatch_event_target" "target_check" { 
  rule = aws_cloudwatch_event_rule.onprem_check_rule.name
  arn  = aws_lambda_function.dms_automation.arn 
}

# [6] 권한 부여 (수정됨: 세미콜론 제거 및 줄바꿈 적용)
resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dms_automation.function_name
  principal     = "events.amazonaws.com"
}
