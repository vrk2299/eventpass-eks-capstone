param(
  [string]$Region = "ap-south-1",
  [string]$ClusterName = "eventpass"
)
$ErrorActionPreference = "Stop"
aws eks update-kubeconfig --name $ClusterName --region $Region
eksctl utils associate-iam-oidc-provider --cluster $ClusterName --region $Region --approve

$policyName = "$ClusterName-AWSLoadBalancerControllerPolicy"
$existingArn = aws iam list-policies --scope Local --query "Policies[?PolicyName=='$policyName'].Arn | [0]" --output text
if (-not $existingArn -or $existingArn -eq "None") {
  $policyPath = Join-Path $env:TEMP "$policyName.json"
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json" -OutFile $policyPath
  $existingArn = aws iam create-policy --policy-name $policyName --policy-document "file://$policyPath" --query Policy.Arn --output text
  Remove-Item -LiteralPath $policyPath -Force
}

$serviceAccount = "aws-load-balancer-controller"
$namespace = "kube-system"
$roleName = "$ClusterName-aws-load-balancer-controller"
eksctl create iamserviceaccount --cluster $ClusterName --region $Region --namespace $namespace --name $serviceAccount --role-name $roleName --attach-policy-arn $existingArn --approve --override-existing-serviceaccounts
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
$chartRoot = Join-Path $env:TEMP "$ClusterName-lbc-chart"
New-Item -ItemType Directory -Force -Path $chartRoot | Out-Null
helm pull eks/aws-load-balancer-controller --version 1.14.0 --untar --untardir $chartRoot
$chartPath = Join-Path $chartRoot "aws-load-balancer-controller"
kubectl apply -f (Join-Path $chartPath "crds/crds.yaml")
$vpcId = aws eks describe-cluster --name $ClusterName --region $Region --query cluster.resourcesVpcConfig.vpcId --output text
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller --namespace kube-system --version 1.14.0 --set clusterName=$ClusterName --set serviceAccount.create=false --set serviceAccount.name=$serviceAccount --set region=$Region --set vpcId=$vpcId
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=5m
kubectl apply -f (Join-Path $PSScriptRoot "../k8s/base/namespace.yaml") -f (Join-Path $PSScriptRoot "../k8s/base/rbac.yaml")
Remove-Item -LiteralPath $chartRoot -Recurse -Force
Write-Host "AWS Load Balancer Controller is ready."
