output "alb_dns_name" {
  description = "URL aplikasi (akses via browser)"
  value       = aws_lb.app.dns_name
}

output "alb_target_group_arn" {
  description = "ARN Target Group ALB — dipakai saat setup ASG manual"
  value       = aws_lb_target_group.app.arn
}

output "rds_endpoint" {
  description = "RDS endpoint — isi ke DB_HOST di .env"
  value       = aws_db_instance.main.address
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint — isi ke REDIS_HOST di .env"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "s3_bucket_name" {
  description = "Nama S3 bucket — isi ke AWS_BUCKET di .env"
  value       = aws_s3_bucket.uploads.bucket
}

output "cloudfront_domain" {
  description = "CloudFront URL — isi ke AWS_URL di .env"
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

output "ec2_security_group_id" {
  description = "Security Group ID untuk EC2 — pilih ini saat launch instance"
  value       = aws_security_group.app.id
}

output "iam_instance_profile_name" {
  description = "IAM Instance Profile — attach ke EC2 saat launch"
  value       = aws_iam_instance_profile.app.name
}

output "app_private_subnet_id" {
  description = "Subnet ID untuk EC2 (AZ1) — pilih ini saat launch instance"
  value       = aws_subnet.app_private[0].id
}
