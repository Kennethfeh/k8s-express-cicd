#!/bin/bash
set -e

CLUSTER_NAME="devops-project-3"
AWS_REGION="us-east-1"

echo "🚀 Installing AWS Load Balancer Controller"

# Get OIDC issuer URL
OIDC_ISSUER_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text)
echo "OIDC Issuer: $OIDC_ISSUER_URL"

# Create IAM policy for ALB controller
if ! aws iam get-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy > /dev/null 2>&1; then
    echo "Creating IAM policy..."
    curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
    aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json
    rm iam_policy.json
else
    echo "IAM policy already exists"
fi

# Create IAM role for service account
cat > aws-load-balancer-controller-service-account.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKSLoadBalancerControllerRole
EOF

# Create trust policy
cat > load-balancer-role-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/${OIDC_ISSUER_URL#*//}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_ISSUER_URL#*//}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
                    "${OIDC_ISSUER_URL#*//}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

# Create IAM role
if ! aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole > /dev/null 2>&1; then
    echo "Creating IAM role..."
    aws iam create-role --role-name AmazonEKSLoadBalancerControllerRole --assume-role-policy-document file://load-balancer-role-trust-policy.json
    aws iam attach-role-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy --role-name AmazonEKSLoadBalancerControllerRole
else
    echo "IAM role already exists"
fi

# Apply service account
kubectl apply -f aws-load-balancer-controller-service-account.yaml

# Install AWS Load Balancer Controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait

# Verify installation
echo "✅ Verifying AWS Load Balancer Controller installation..."
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Install metrics server for HPA
echo "📊 Installing metrics server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait for metrics server
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=300s

echo "🎉 AWS Load Balancer Controller installation completed!"

# Cleanup
rm -f aws-load-balancer-controller-service-account.yaml
rm -f load-balancer-role-trust-policy.json

