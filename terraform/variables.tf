variable "name" {
  description = "Short unique prefix for lab resource names. Keep under 20 characters."
  type        = string
  default     = "eventpass-class"
}
variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-south-1"
}
variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}
variable "mysql_engine_version" {
  description = "Optional exact RDS MySQL engine version. Leave null to use the AWS regional default."
  type        = string
  default     = null
}
variable "node_instance_type" {
  description = "EC2 type for the single classroom node."
  type        = string
  default     = "t3.medium"
}
variable "db_instance_class" {
  description = "RDS class for a small classroom workload."
  type        = string
  default     = "db.t3.micro"
}
variable "ecr_repository" {
  type    = string
  default = "eventpass"
}
variable "github_owner" {
  description = "GitHub user or organization that owns the repo."
  type        = string
  default     = "vrk2299"
}
variable "github_repository" {
  description = "New repository name used by GitHub Actions OIDC trust."
  type        = string
  default     = "eventpass-eks-capstone"
}
variable "github_owner_id" {
  description = "Immutable numeric GitHub owner ID, retrieved with scripts/get-github-ids.ps1."
  type        = string
}
variable "github_repository_id" {
  description = "Immutable numeric GitHub repo ID, retrieved after creating the repository."
  type        = string
}
