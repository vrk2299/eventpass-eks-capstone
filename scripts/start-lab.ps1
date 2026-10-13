param(
  [string]$TerraformDir = (Join-Path $PSScriptRoot "../terraform")
)
$ErrorActionPreference = "Stop"
Push-Location $TerraformDir
try {
  terraform init
  terraform plan -out classroom.tfplan
  Write-Host "Review the plan and expected costs in AWS Pricing Calculator. This creates billable AWS resources."
  $answer = Read-Host "Type CREATE to create this classroom environment"
  if ($answer -cne "CREATE") { throw "Setup cancelled. No Terraform apply was run." }
  terraform apply classroom.tfplan
  $cluster = terraform output -raw cluster_name
  $region = terraform output -raw aws_region
  & (Join-Path $PSScriptRoot "bootstrap-alb-controller.ps1") -Region $region -ClusterName $cluster
  Write-Host "Infrastructure and ingress controller are ready. Add the Terraform outputs and app secrets to GitHub Actions, then push to main to deploy."
} finally {
  Pop-Location
}
