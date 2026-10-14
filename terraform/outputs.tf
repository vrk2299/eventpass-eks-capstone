output "cluster_name" {
  value = module.eks.cluster_name
}
output "aws_region" {
  value = var.aws_region
}
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
output "rds_endpoint" {
  value = aws_db_instance.this.address
}
output "rds_database_name" {
  value = aws_db_instance.this.db_name
}
output "rds_master_username" {
  value = aws_db_instance.this.username
}
output "rds_secret_arn" {
  value     = aws_db_instance.this.master_user_secret[0].secret_arn
  sensitive = true
}
output "github_deployer_role_arn" {
  value = aws_iam_role.github_deployer.arn
}
output "vpc_id" {
  value = module.vpc.vpc_id
}
output "public_subnet_ids" {
  value = module.vpc.public_subnets
}
output "private_subnet_ids" {
  value = module.vpc.private_subnets
}
