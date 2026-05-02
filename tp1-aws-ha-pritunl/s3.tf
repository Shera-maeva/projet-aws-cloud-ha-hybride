###############################################################################
# S3 Bucket pour le stockage applicatif
###############################################################################

resource "aws_s3_bucket" "app" {
  # Le suffixe random garantit un nom unique globalement
  bucket = "${local.name_prefix}-storage-${random_id.suffix.hex}"

  tags = {
    Name = "${local.name_prefix}-storage"
  }
}

# -----------------------------------------------------------------------------
# Versioning activé pour la protection des données
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# Chiffrement côté serveur AES256
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# Bloquer tout accès public (best practice)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Lifecycle policy — déplace les anciennes versions en Glacier après 30j
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    filter {
      prefix = "" # toutes les clés
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# -----------------------------------------------------------------------------
# Notification S3 -> Lambda à chaque upload
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "app" {
  bucket = aws_s3_bucket.app.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
