###############################################################################
# Outputs — informations utiles après le déploiement
###############################################################################

output "vpc_id" {
  description = "ID du VPC créé"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "DNS de l'Application Load Balancer (URL d'accès Pritunl)"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL HTTPS complète d'accès à Pritunl"
  value       = "https://${aws_lb.main.dns_name}"
}

output "asg_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = aws_autoscaling_group.pritunl.name
}

output "rds_endpoint" {
  description = "Endpoint RDS MySQL (privé)"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "Adresse RDS (sans le port)"
  value       = aws_db_instance.main.address
}

output "s3_bucket_name" {
  description = "Nom du bucket S3"
  value       = aws_s3_bucket.app.id
}

output "s3_bucket_arn" {
  description = "ARN du bucket S3"
  value       = aws_s3_bucket.app.arn
}

output "lambda_function_name" {
  description = "Nom de la fonction Lambda"
  value       = aws_lambda_function.processor.function_name
}

output "public_subnet_ids" {
  description = "IDs des subnets publics"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs des subnets privés"
  value       = aws_subnet.private[*].id
}

output "db_subnet_ids" {
  description = "IDs des subnets BDD"
  value       = aws_subnet.db[*].id
}

output "availability_zones" {
  description = "AZ utilisées"
  value       = local.azs
}

output "next_steps" {
  description = "Prochaines étapes"
  value       = <<-EOT

    ===== DÉPLOIEMENT TERMINÉ =====

    1. Attendre 5-10 minutes que les EC2 finissent l'install de Pritunl

    2. Accéder à l'interface Pritunl:
       URL: https://${aws_lb.main.dns_name}
       (accepter le certif self-signed)

    3. Récupérer la setup-key et le mot de passe par défaut depuis une instance:
       - Connexion via SSM Session Manager (recommandé)
       - Ou SSH si une key pair a été configurée
       - Lire le fichier /home/ubuntu/pritunl-info.txt
       - Ou exécuter:
           sudo pritunl setup-key
           sudo pritunl default-password

    4. Pour obtenir les IPs publiques des instances:
       aws ec2 describe-instances \\
         --filters "Name=tag:AutoScalingGroup,Values=${aws_autoscaling_group.pritunl.name}" \\
                   "Name=instance-state-name,Values=running" \\
         --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \\
         --output table \\
         --region ${var.aws_region}

  EOT
}
