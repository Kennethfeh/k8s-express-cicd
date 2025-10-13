# DevOps Project 3 — Kubernetes on AWS EKS

I built this project to prove end-to-end ownership of a cloud-native platform: from raw infrastructure to a live service behind an AWS Application Load Balancer. The starting point was the Node.js app from my containers project; everything else—Terraform, Kubernetes assets, Helm packaging, IAM, automation, and validation—was created here.

---

## Overview

- **Stack:** Amazon EKS, Terraform, Kubernetes, Helm, Node.js/Express, GitHub Actions, AWS Load Balancer Controller.
- **Objective:** run a real application on EKS with production-style health checks, autoscaling, ingress, and CI/CD.
- **Outcome:** a reproducible platform that anyone with AWS credentials can stand up (and destroy) in a few minutes.

---

## Infrastructure as Code (terraform/)

Terraform provisions everything the cluster needs:

- VPC with public/private subnets, routing, and NAT gateways.
- IAM roles/policies for the EKS control plane, node group, GitHub Actions, and the ALB controller.
- EKS cluster plus a managed node group (default `t3.micro` for free-tier alignment, but scalable for load tests).
- Amazon ECR repository and an OIDC provider so GitHub Actions can assume AWS roles without static credentials.

Each apply prints the kubeconfig command and ECR URL; `terraform destroy` tears down the stack when I’m finished to avoid charges.

---

## Application & Packaging (app/, kubernetes/, helm/)

- `app/` contains the Express service with endpoints for `/health`, `/ready`, `/live`, `/metrics`, and synthetic load (`/load/<n>`). The Dockerfile produces a small, non-root image.
- `kubernetes/` holds raw manifests—namespace, deployment, service, HPA, and ingress—for direct `kubectl apply` workflows.
- `helm/devops-app-chart/` mirrors those workloads as a Helm chart so I can install or upgrade with overridable values.

---

## Platform Automation (scripts/)

- `install-alb-controller.sh` creates/updates the IAM policy, bootstraps the AWS Load Balancer Controller, and annotates the Kubernetes service account.
- Metrics Server receives the EKS-required flags (`--kubelet-insecure-tls`, `--kubelet-preferred-address-types=InternalIP`) via a patch so the HPA can access CPU and memory metrics.
- The HPA scales between one and three replicas. I confirmed behaviour by driving the `/load/10` route with `hey` while watching `kubectl get hpa`.

---

## CI/CD ( .github/workflows/deploy.yml )

GitHub Actions runs three stages whenever I push:

1. Install dependencies and run tests (placeholder today, ready for unit tests tomorrow).
2. On `main`, assume the GitHub Actions role, log in to ECR, build/push the image tagged with the commit SHA and `latest`.
3. Update kubeconfig, set the deployment image, wait for the rollout, and curl the ALB `/health` and `/` endpoints before declaring success.

Required secrets:

| Secret | Purpose |
| --- | --- |
| `AWS_ACCOUNT_ID` | Builds the ECR image URL. |
| `AWS_ROLE_ARN` (optional) | Explicit ARN if I don’t want to derive the role inside the workflow. |

---

## Observability & Validation

I give myself the same signals I’d expect in production:

- `/health`, `/ready`, and `/live` feed Kubernetes probes and ALB health checks.
- `/metrics` exposes Prometheus-style counters and gauges to prove telemetry wiring.
- `hey -z 120s -c 10 http://$ALB_HOST/load/10` exercises the HPA and validates the cluster under stress.
- Routine commands (`kubectl get pods -n kube-system`, `kubectl logs …`) verify controllers and metrics after every change.

---

## Run It Yourself

```bash
# 1. Provision infrastructure
+ cd terraform
+ terraform init
+ terraform apply

# 2. Build and publish the application
+ cd ../app
+ npm ci && npm test
+ ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
+ aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_URL"
+ docker build -t "$ECR_URL:latest" .
+ docker push "$ECR_URL:latest"

# 3. Deploy to the cluster (manifests path)
+ cd ..
+ kubectl apply -f kubernetes/namespace.yaml
+ kubectl apply -f kubernetes/deployment.yaml
+ kubectl apply -f kubernetes/service.yaml
+ kubectl apply -f kubernetes/hpa.yaml
+ kubectl apply -f kubernetes/ingress.yaml
+ ./scripts/install-alb-controller.sh
+ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
+ kubectl patch deployment metrics-server -n kube-system \
+     --type=json \
+     -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
+          {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}]'
+ kubectl get pods -n devops-app
+ kubectl get ingress -n devops-app
```

Prefer Helm? `helm install devops-app ./helm/devops-app-chart -n devops-app --create-namespace` delivers the same resources.

---

## Tear Down

- `terraform destroy` removes the AWS footprint (EKS, ALB, NAT gateways, VPC, etc.).
- `helm uninstall devops-app -n devops-app` or `kubectl delete namespace devops-app` clears the workloads.
- Delete any local helpers such as the `hey` binary.

---

## Why This Matters (for recruiters and hiring managers)

- I own the full lifecycle: infra, application changes, automation, validation, and cleanup.
- AWS integration is scripted end-to-end—no manual IAM tweaks or guessing which permissions are required.
- Operability is built in: probes, metrics, autoscaling, and smoke tests run before a deployment is considered healthy.
- Helm and raw manifests live side by side so teams can evolve from manual changes to templated releases without a rewrite.
- The CI/CD pipeline doesn’t stop at “docker push”; it validates the live service fronted by an AWS ALB.

Clone the repo, follow the steps above, and you can see the same platform running in your own AWS account.
