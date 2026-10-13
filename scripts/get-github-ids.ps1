param(
  [string]$Owner = "vrk2299",
  [string]$Repository = "eventpass-eks-capstone"
)
$ErrorActionPreference = "Stop"
$ownerInfo = Invoke-RestMethod -Uri "https://api.github.com/users/$Owner" -Headers @{ "Accept" = "application/vnd.github+json" }
$repoInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repository" -Headers @{ "Accept" = "application/vnd.github+json" }
Write-Host "GitHub owner ID:      $($ownerInfo.id)"
Write-Host "GitHub repository ID: $($repoInfo.id)"
Write-Host "Copy these numeric IDs to terraform/terraform.tfvars."
