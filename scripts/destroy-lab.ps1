param(
  [string]$TerraformDir = (Join-Path $PSScriptRoot "../terraform"),
  [switch]$SkipKubernetesCleanup
)
$ErrorActionPreference = "Stop"
if (-not $SkipKubernetesCleanup) {
  $cluster = terraform "-chdir=$TerraformDir" output -raw cluster_name 2>$null
  $region = terraform "-chdir=$TerraformDir" output -raw aws_region 2>$null
  if ($cluster -and $region) {
    aws eks update-kubeconfig --name $cluster --region $region
    kubectl delete namespace eventpass --wait=true --ignore-not-found=true
    Write-Host "Waiting for the controller to remove the classroom ALB..."
    $albStillExists = $false
    for ($attempt = 1; $attempt -le 24; $attempt++) {
      $albArns = aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[].LoadBalancerArn" --output text
      $albStillExists = $false
      foreach ($albArn in ($albArns -split "\s+" | Where-Object { $_ -and $_ -ne "None" })) {
        $tagJson = aws elbv2 describe-tags --region $region --resource-arns $albArn --output json | ConvertFrom-Json
        $isClassroomAlb = $tagJson.TagDescriptions[0].Tags | Where-Object { $_.Key -eq "elbv2.k8s.aws/cluster" -and $_.Value -eq $cluster }
        if ($isClassroomAlb) { $albStillExists = $true; break }
      }
      if (-not $albStillExists) { break }
      Start-Sleep -Seconds 15
    }
    if ($albStillExists) { throw "The classroom ALB still exists. Check the AWS Load Balancer Controller before destroying the VPC." }
    eksctl delete iamserviceaccount --cluster $cluster --region $region --namespace kube-system --name aws-load-balancer-controller --wait 2>$null
    eksctl utils disassociate-iam-oidc-provider --cluster $cluster --region $region --approve 2>$null
    $policyName = "$cluster-AWSLoadBalancerControllerPolicy"
    $policyArn = aws iam list-policies --scope Local --query "Policies[?PolicyName=='$policyName'].Arn | [0]" --output text
    if ($policyArn -and $policyArn -ne "None") {
      aws iam delete-policy --policy-arn $policyArn
    }
  }
}
Push-Location $TerraformDir
try {
  terraform destroy
} finally {
  Pop-Location
}
Write-Host "Terraform resources removed. Confirm the EKS cluster, RDS database, NAT gateway, and load balancers are gone in AWS."
