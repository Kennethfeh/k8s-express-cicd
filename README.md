# DevOps Project 3 – Kubernetes on AWS EKS

End-to-end DevOps showcase that takes a containerised Node.js application from local development to a production-ready deployment on Amazon Elastic Kubernetes Service (EKS). The project highlights how infrastructure-as-code, Kubernetes packaging, and CI/CD automation come together to deliver features safely and repeatedly.

---

## 🚀 What You Built

- **Fully managed EKS cluster** provisioned with Terraform (networking, IAM roles, managed node group, ECR, OIDC).
- **Containerised Express service** with health/readiness/liveness endpoints, metrics, and load-test routes.
- **Helm chart** (`helm/devops-app-chart`) that packages the Deployment, Service, probes, and environment configuration with sensible defaults.
- **Kubernetes manifests** for direct `kubectl apply` workflows (`kubernetes/` namespace, deployment, service, HPA, ingress).
- **AWS Load Balancer Controller** installed via script to manage the ALB ingress lifecycle.
- **Horizontal Pod Autoscaling** driven by Metrics Server patching for EKS-specific kubelet flags.
- **GitHub Actions pipeline** that tests, builds, pushes to ECR, and deploys to the cluster with rollout verification.
- **Operational tooling** including ALB controller bootstrap, ECR login helper, and load testing with `hey`.

---

## 🧱 Architecture Overview

```
Developer ➜ GitHub Actions ➜ AWS ECR ➜ Amazon EKS (Fargate-ready)
                                            │
                                      AWS Load Balancer Controller ➜ ALB ➜ Users
```

- Terraform builds the VPC, public/private subnets, NAT gateways, IAM roles, the EKS cluster, and a managed node group (default `t3.micro`, scalable for tests).
- Application traffic enters via an AWS Application Load Balancer managed by the controller, hitting the ingress -> service -> pods.
- HPA monitors CPU/Memory via Metrics Server and scales replicas (1–3) when thresholds are exceeded.
- CI/CD pushes immutable images to ECR and performs rolling updates with Kubernetes native rollout tracking.

---

## 📂 Repository Map

| Path | Purpose |
| --- | --- |
| `app/` | Node.js 18 Express API, Dockerfile, tests placeholder. |
| `helm/devops-app-chart/` | Parameterised Helm chart (values, helpers, resource templates). |
| `kubernetes/` | Raw manifests for namespace, deployment, service, HPA, ingress. |
| `scripts/install-alb-controller.sh` | Idempotent installer for AWS Load Balancer Controller + IAM wiring. |
| `terraform/` | Infrastructure-as-code for networking, EKS cluster, node group, ECR, OIDC provider. |
| `.github/workflows/deploy.yml` | CI/CD pipeline (test → build/push → deploy & smoke checks). |

---

## ⚙️ Provisioning the Platform

```bash
# Bootstrap Terraform
cd terraform
terraform init
terraform apply                 # creates VPC, EKS, node group, ECR, IAM, etc.

# (Optional) resize node group for heavier tests
terraform apply -var 'node_desired_size=2' -var 'node_max_size=3'
```

Outputs include the cluster endpoint, kubeconfig command, and ECR URL. Destroy with `terraform destroy` when finished to control costs.

---

## 🐳 Building & Publishing the App

```bash
# Install deps and run placeholder tests
cd app
npm ci
npm test

# Build & push image
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_URL"
docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"
```

---

## ☸️ Deploying to Kubernetes

```bash
# Create namespace & workloads (manifests route)
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml
kubectl apply -f kubernetes/ingress.yaml

# Install AWS Load Balancer Controller
./scripts/install-alb-controller.sh

# Install Metrics Server with EKS-friendly flags
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
       {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}]'

# Check everything
kubectl get pods -n devops-app
kubectl describe hpa devops-app-hpa -n devops-app
kubectl get ingress -n devops-app
```

**Helm path:** `helm install devops-app ./helm/devops-app-chart -n devops-app --create-namespace`

---

## 🤖 CI/CD Workflow Highlights

1. **Test job** – installs Node.js deps, runs `npm test`.
2. **Build job** – assumes `GitHubActionsRole`, logs into ECR, builds & pushes image tagged with both `SHA` and `latest`.
3. **Deploy job** – updates kubeconfig, patches the deployment image, waits for rollout, probes `/health` via ALB.

Secrets required:

| Secret | Description |
| --- | --- |
| `AWS_ACCOUNT_ID` | Account ID hosting EKS/ECR. |
| `AWS_ROLE_ARN` *(optional alternative)* | Role to assume if you prefer explicit ARN. |

---

## 🔍 Observability & Testing

- **Health endpoints**: `/health`, `/ready`, `/live` (wired to probes & ALB checks).
- **Metrics**: `/metrics` exposes basic Prometheus-style counters and gauges.
- **Load test**: `hey -z 120s -c 10 http://$ALB_HOST/load/10` verifies autoscaling response.
- **kubectl commands** provide live cluster introspection, e.g. `kubectl get pods -n kube-system` to ensure controller/metrics are healthy.

---

## 🧹 Cleanup Checklist

- `terraform destroy` to tear down AWS resources (VPC, ALB, EKS, NAT gateways, etc.).
- `helm uninstall devops-app -n devops-app` or `kubectl delete namespace devops-app` for cluster-only cleanup.
- Remove temporary tooling (`rm hey*`) if downloaded locally.

---

## 📚 Talking Points for Recruiters

- Demonstrated ownership of the **full delivery pipeline**: infrastructure, application, automation, and verification.
- Automated **IAM, OIDC, and controller install**, showing comfort with AWS service integration.
- Implemented **scaling & health strategies** (probes, HPA, metrics server modifications).
- Built a reusable **Helm chart** alongside raw manifests to support different deployment workflows.
- Added **CI/CD with rollout validation**, echoing real-world GitOps/DevOps practices.
- Documented **load testing and operational procedures**, evidencing production-readiness awareness.

> ✅ The repository is intended to be fork-and-run: anyone with an AWS account and GitHub credentials can reproduce the stack by following the steps above.
