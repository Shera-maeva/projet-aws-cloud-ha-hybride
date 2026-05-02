###############################################################################
# Outputs - infos utiles apres deploiement
###############################################################################

output "vpc_id_used" {
  description = "VPC du TP1 reutilise"
  value       = local.vpc_id
}

output "alb_dns_name" {
  description = "DNS de l ALB Odoo"
  value       = aws_lb.odoo.dns_name
}

output "alb_url" {
  description = "URL d acces a Odoo via le LB"
  value       = "http://${aws_lb.odoo.dns_name}"
}

output "odoo_master_public_ip" {
  description = "IP publique du noeud Master"
  value       = aws_eip.odoo_master.public_ip
}

output "odoo_slave_public_ip" {
  description = "IP publique du noeud Slave"
  value       = aws_eip.odoo_slave.public_ip
}

output "odoo_master_private_ip" {
  description = "IP privee du noeud Master"
  value       = aws_instance.odoo_master.private_ip
}

output "odoo_slave_private_ip" {
  description = "IP privee du noeud Slave"
  value       = aws_instance.odoo_slave.private_ip
}

output "odoo_master_instance_id" {
  description = "Instance ID du Master"
  value       = aws_instance.odoo_master.id
}

output "odoo_slave_instance_id" {
  description = "Instance ID du Slave"
  value       = aws_instance.odoo_slave.id
}

output "odoo_master_url_direct" {
  description = "URL directe du Master Odoo"
  value       = "http://${aws_eip.odoo_master.public_ip}:8069"
}

output "odoo_slave_url_direct" {
  description = "URL directe du Slave Odoo"
  value       = "http://${aws_eip.odoo_slave.public_ip}:8069"
}

output "next_steps" {
  description = "Prochaines etapes apres deploiement"
  value       = <<-EOT

    ===== TP2 DEPLOIEMENT TERMINE =====

    Patientez 8-12 minutes pour que Docker + Odoo + Postgres finissent l install.

    1. ACCES ODOO:
       Via le Load Balancer: http://${aws_lb.odoo.dns_name}
       Master direct       : http://${aws_eip.odoo_master.public_ip}:8069
       Slave direct        : http://${aws_eip.odoo_slave.public_ip}:8069

    2. INITIALISATION ODOO (sur les 2 noeuds avec MEMES valeurs):
       - Master Password: voir terraform.tfvars (odoo_admin_password)
       - Database Name: odoo (EXACTEMENT)
       - Email: admin@tp2.local
       - Password: choisir le meme sur les 2
       - DECOCHER Demo data!

    3. CONFIGURATION BUCARDO:
       aws ssm start-session --target ${aws_instance.odoo_master.id} --region ${var.aws_region}
       cd /opt/odoo
       sudo ./setup-bucardo.sh ${aws_instance.odoo_slave.private_ip}

    4. VOIR STATUT BUCARDO:
       sudo bucardo status
       sudo bucardo list syncs

    5. TEST FAILOVER:
       aws ec2 stop-instances --instance-ids ${aws_instance.odoo_master.id} --region ${var.aws_region}

  EOT
}