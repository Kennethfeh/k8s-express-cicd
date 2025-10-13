# DevOps Project 3 — Kubernetes on AWS EKS

This repository is the third milestone in my DevOps journey. I took the Node.js service from the containers project and built out everything needed to run it on Amazon EKS: infrastructure-as-code, Kubernetes packaging, CI/CD, and the operational guardrails you would expect in production.

---

## Highlights

- Provisioned an EKS cluster with Terraform: VPC, subnets, IAM roles, node group (t3.micro by default), ECR repository, and OIDC provider.
- Refined the Express API so it exposes `/health`, `/ready`, `/live`, `/metrics`, and synthetic load endpoints that exercise probes and autoscaling.
- Packaged the workloads two ways—raw manifests for quick apply cycles and a Helm chart for repeatable releases.
- Automated installation of the AWS Load Balancer Controller plus all required IAM so an Application Load Balancer fronts the service.
- Patched Metrics Server with the EKS-friendly flags and verified Horizontal Pod Autoscaling (1–3 replicas) with load tests using `hey`.
- Built a GitHub Actions pipeline that tests, builds, pushes to ECR, rolls out to EKS, then smoke-tests the ALB before marking the deployment green.

---

## Architecture at a Glance

```
Developer → GitHub Actions → Amazon ECR → Amazon EKS
                                  │
                            AWS Load Balancer Controller → ALB → Users
```

- Terraform sets up networking, security, and cluster resources end to end.
- Traffic flows from the ALB to the ingress, then through the service to the pods.
- Metrics Server + HPA watch CPU/memory and scale the deployment between one and three replicas under load.
- CI/CD pushes immutable images to ECR and performs rolling updates with rollout verification.

---

## Repository Map

| Path | Purpose |
| --- | --- |
| `app/` | Node.js 18 Express service, Dockerfile, placeholder tests. |
| `helm/devops-app-chart/` | Helm chart (values, helpers, templated manifests). |
| `kubernetes/` | Raw manifests for namespace, deployment, service, HPA, ingress. |
| `scripts/` | Utility scripts, including the ALB controller installer. |
| `terraform/` | Terraform configuration for networking, EKS, node groups, IAM, ECR. |
| `.github/workflows/deploy.yml` | GitHub Actions pipeline (test → build/push → deploy + smoke tests). |

---

## Provisioning the Platform

```bash
cd terraform
terraform init
terraform apply            # creates VPC, EKS, node group, ECR, IAM, etc.

# Optional: give the cluster more room for load tests
terraform apply -var 'node_desired_size=2' -var 'node_max_size=3'
```

Outputs include the cluster endpoint, kubeconfig command, and ECR repository URL. Run `terraform destroy` when you are finished to avoid surprise AWS costs.

---

## Building & Publishing the App

```bash
cd app
npm ci
npm test

ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "$ECR_URL"

docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"
```

---

## Deploying to Kubernetes

```bash
# Namespace + workloads (manifest path)
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml
kubectl apply -f kubernetes/ingress.yaml

# Load balancer controller + metrics server tweaks
./scripts/install-alb-controller.sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
       {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}]'

# Sanity checks
kubectl get pods -n devops-app
kubectl describe hpa devops-app-hpa -n devops-app
kubectl get ingress -n devops-app
```

**Helm alternative:** `helm install devops-app ./helm/devops-app-chart -n devops-app --create-namespace`

---

## CI/CD Workflow Highlights

1. Run Node.js tests on every push.
2. On `main`, assume the GitHub Actions role, log in to ECR, build/push images tagged with the SHA and `latest`.
3. Update kubeconfig, set the image on the deployment, wait for rollout, then curl the ALB `/health` and root endpoints.

Secrets required:

| Secret | Why it’s needed |
| --- | --- |
| `AWS_ACCOUNT_ID` | Builds the ECR image URL. |
| `AWS_ROLE_ARN` (optional) | Use a fixed IAM role if you prefer to pass the ARN rather than the account ID. |

---

## Observability & Testing

I exposed enough surface area to prove that the platform is working:

- `/health`, `/ready`, and `/live` drive both Kubernetes probes and ALB health checks.
- `/metrics` exports simple Prometheus gauges/counters so instrumentation can be tested quickly.
- Synthetic load endpoints (`/load/5`, `/load/10`, etc.) let me drive the HPA with `hey -z 120s -c 10 http://$ALB_HOST/load/10`.
- Routine cluster checks (`kubectl get pods -n kube-system`, `kubectl logs …`) give quick assurance that controllers and metrics are healthy.

---

## Cleanup Checklist

- `terraform destroy` to remove the AWS resources (VPC, ALB, EKS, NAT gateways, etc.).
- `helm uninstall devops-app -n devops-app` or `kubectl delete namespace devops-app` if you deployed manually.
- Remove any temporary tooling (`rm hey*`) from your workstation.

---

## Notes for Recruiters

- I owned the full delivery path here: infrastructure, application changes, automation, and verification.
- IAM, OIDC, and the load balancer controller are scripted so the AWS integration is repeatable.
- Probes, Metrics Server tweaks, and the HPA show that I think about operations and scaling, not just “it runs on my machine”.
- The Helm chart mirrors the raw manifests, giving teams an easy migration path from ad-hoc deployments to templates.
- GitHub Actions performs smoke tests against the ALB before the job turns green—matching the rollout hygiene I expect in production.

Anyone with an AWS account and GitHub credentials can clone this repo and reproduce the platform by following the steps above.
