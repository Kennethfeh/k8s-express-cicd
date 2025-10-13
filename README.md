# DevOps Project 3 — Kubernetes on AWS EKS

I built this project to show end-to-end ownership of a cloud-native platform: from raw AWS infrastructure to a live service behind an Application Load Balancer. The starting point was the Node.js app from my containers project; everything else—Terraform, Kubernetes assets, Helm packaging, IAM plumbing, automation, and validation—was created here.

---

## Overview

- **Stack:** Amazon EKS, Terraform, Kubernetes, Helm, Node.js/Express, GitHub Actions, AWS Load Balancer Controller.
- **Goal:** run a real application on EKS with production-style health checks, autoscaling, ingress, and CI/CD.
- **Result:** a repeatable platform that anyone with AWS credentials can stand up (and tear down) in a few minutes.

---

## Infrastructure as Code (`terraform/`)

Terraform provisions everything the cluster needs:

- VPC with public/private subnets, routing, and NAT gateways.
- IAM roles and policies for the control plane, node group, GitHub Actions, and the ALB controller.
- EKS cluster plus a managed node group (default `t3.micro` for the free tier, with variables to scale up for load tests).
- Amazon ECR repository and an OIDC provider so GitHub Actions can assume AWS roles without static credentials.

Each `terraform apply` prints the kubeconfig command and ECR URL. When I’m finished, `terraform destroy` tears the stack down so I don’t leave resources running.

---

## Application & Packaging (`app/`, `kubernetes/`, `helm/`)

- `app/` contains the Express service with `/health`, `/ready`, `/live`, `/metrics`, and `/load/<n>` endpoints. The Dockerfile builds a small, non-root image.
- `kubernetes/` keeps the raw manifests (namespace, deployment, service, HPA, ingress) for fast `kubectl apply` workflows.
- `helm/devops-app-chart/` mirrors those workloads as a Helm chart so I can roll out the same stack with templated values.

---

## Platform Automation (`scripts/`)

- `install-alb-controller.sh` installs the AWS Load Balancer Controller, creates/updates its IAM policy, and annotates the Kubernetes service account.
- Metrics Server is patched with the EKS-specific flags (`--kubelet-insecure-tls`, `--kubelet-preferred-address-types=InternalIP`) so the Horizontal Pod Autoscaler has usable CPU and memory metrics.
- The HPA scales between one and three replicas. I validated it by hammering `/load/10` with `hey` while watching `kubectl get hpa`.

---

## CI/CD (`.github/workflows/deploy.yml`)

The GitHub Actions pipeline covers the delivery path:

1. Install dependencies and run tests (ready for unit tests when I add them).
2. On `main`, assume the GitHub Actions role, log in to ECR, build/push the image tagged with both the commit SHA and `latest`.
3. Update kubeconfig, patch the deployment image, wait for the rollout, and curl the ALB `/health` and `/` endpoints before declaring success.

Secrets I use:

| Secret | Purpose |
| --- | --- |
| `AWS_ACCOUNT_ID` | Builds the ECR image URL. |
| `AWS_ROLE_ARN` (optional) | Explicit role ARN if I don’t want to derive it from the account ID. |

---

## Observability & Validation

- `/health`, `/ready`, and `/live` feed Kubernetes probes and ALB health checks.
- `/metrics` exposes Prometheus-style counters/gauges so I can confirm telemetry wiring.
- `hey -z 120s -c 10 http://$ALB_HOST/load/10` exercises the HPA while I watch pods scale and metrics change.
- `kubectl get pods -n kube-system` and targeted `kubectl logs` calls make it easy to verify controllers after each change.

---

## Run It Yourself

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply

# 2. Build and publish the application
cd ../app
npm ci
npm test
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_URL"
docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"

# 3. Deploy to the cluster (manifests path)
cd ..
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml
kubectl apply -f kubernetes/ingress.yaml
./scripts/install-alb-controller.sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
       {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}]'

kubectl get pods -n devops-app
kubectl get ingress -n devops-app
```

Prefer Helm? `helm install devops-app ./helm/devops-app-chart -n devops-app --create-namespace` deploys the same stack.

---

## Tear Down

- `terraform destroy` removes the AWS footprint (EKS, ALB, NAT gateways, VPC, etc.).
- `helm uninstall devops-app -n devops-app` or `kubectl delete namespace devops-app` cleans up the workloads.
- Delete any local helpers such as the `hey` binary when you’re done.

---

## Final Notes

This is the kit I use when I need to demo or experiment with EKS. Every step is scripted and documented so there’s no guesswork. Follow the commands above and you’ll get the same environment I run day to day—and you can tear it all back down just as quickly.
