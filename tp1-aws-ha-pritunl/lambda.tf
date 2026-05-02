###############################################################################
# Lambda function pour le traitement serverless des objets S3
###############################################################################

# -----------------------------------------------------------------------------
# IAM Role pour la Lambda
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-lambda-role"
  }
}

# Logs CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Accès VPC (ENI)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Accès au bucket S3
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.name_prefix}-lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Packaging du code Lambda
# -----------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# -----------------------------------------------------------------------------
# Fonction Lambda
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-processor"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # On déploie la Lambda dans le VPC pour qu'elle puisse joindre le RDS
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET   = aws_s3_bucket.app.id
      DB_HOST     = aws_db_instance.main.address
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      ENVIRONMENT = var.environment
      # Note: en prod, le mot de passe doit venir de Secrets Manager
    }
  }

  tags = {
    Name = "${local.name_prefix}-processor"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]
}

# -----------------------------------------------------------------------------
# Permission pour S3 d'invoquer la Lambda
# -----------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.app.arn
}

# -----------------------------------------------------------------------------
# CloudWatch log group avec rétention de 7 jours
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-processor"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-logs"
  }
}
