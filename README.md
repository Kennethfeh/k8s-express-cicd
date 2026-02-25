# Kubernetes Express CI/CD (EKS)

Hands-on blueprint for provisioning AWS EKS with Terraform, packaging a Node.js service, and shipping it through GitHub Actions into the cluster with health checks, autoscaling, and ingress managed by the AWS Load Balancer Controller.

## Solution highlights

- **Infrastructure as Code:** Terraform builds the VPC, subnets, IAM roles, ECR repository, EKS cluster, and managed node group.
- **Application Packaging:** Express app exposes `/`, `/health`, `/ready`, `/live`, `/metrics`, and `/load/:intensity`. Docker image is small, non-root, and probe-friendly.
- **Deployment Options:** Raw Kubernetes manifests for quick applies plus a Helm chart for repeatable upgrades.
- **Automation:** Scripts install the ALB controller, patch Metrics Server, and validate HPA behaviour. GitHub Actions runs tests, builds/pushes the image, and rolls out to the cluster.

## Repository layout

| Path | Description |
| --- | --- |
| `terraform/` | EKS cluster, networking, IAM, and ECR definitions. Outputs include kubeconfig commands and repository URLs. |
| `app/` | Express API + Dockerfile with npm scripts for dev/test/build. |
| `kubernetes/` | Namespaces, Deployment, Service, HPA, and ingress manifests ready for `kubectl apply`. |
| `helm/devops-app-chart/` | Helm chart mirroring the raw manifests with templated values for replicas, image tags, and ingress hosts. |
| `scripts/install-alb-controller.sh` | Bootstraps the AWS Load Balancer Controller with the correct IAM policy + service account annotations. |
| `.github/workflows/deploy.yml` | CI/CD pipeline that tests, builds, and deploys to EKS on pushes to `main`. |

## Prerequisites

- AWS account with permissions for IAM, EKS, EC2, and ECR.
- Terraform ≥ 1.4, AWS CLI v2, kubectl, Helm, and Docker installed locally.
- GitHub OIDC role configured for the repository (if using Actions to deploy).

## Bring the platform up

```bash
cd terraform
terraform init
terraform apply
aws eks update-kubeconfig --name $(terraform output -raw cluster_name) --region $(terraform output -raw region)
```

Terraform outputs the `ecr_repository_url`. Build and push the app image:

```bash
cd ../app
npm ci
npm test
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_URL"
docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"
```

## Deploy workloads

### Raw manifests

```bash
kubectl create namespace devops-app || true
kubectl apply -n devops-app -f kubernetes/
./scripts/install-alb-controller.sh
```

Patch the Kubernetes Metrics Server so the Horizontal Pod Autoscaler works:

```bash
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
       {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}]'
```

### Helm

```bash
helm upgrade --install devops-app helm/devops-app-chart \
  -n devops-app --create-namespace \
  --set image.repository=$(dirname "$ECR_URL")/devops-app \
  --set image.tag=$(git rev-parse --short HEAD)
```

## CI/CD story

1. GitHub Actions job installs dependencies and runs tests.
2. Successful pushes to `main` assume the AWS role, log into ECR, build/push the container, and update the Kubernetes deployment via `kubectl set image`.
3. The workflow waits for the rollout to finish and curls the ALB `/.well-known/health` (or `/health`) endpoint before marking the run green.

Secrets often used:

- `AWS_ACCOUNT_ID`
- `AWS_ROLE_ARN`
- `AWS_REGION`

## Observability & operations

- `/metrics` exposes Prometheus counters/gauges for instrumentation drills.
- `/load/:n` lets you spike CPU to watch the HPA scale between its configured `minReplicas` and `maxReplicas`.
- Ingress resources are annotated for the AWS Load Balancer Controller; check `kubectl get ingress -n devops-app` for URLs.
- Run `kubectl get events -n devops-app --sort-by=.metadata.creationTimestamp` to inspect rollouts and chaos tests.

## Cleanup

```bash
helm uninstall devops-app -n devops-app || kubectl delete namespace devops-app
terraform destroy -auto-approve
```

Destroying the Terraform stack removes the EKS cluster, ALB, NAT gateways, and other billable resources.

Use this project whenever you need a soup-to-nuts example of building on AWS EKS with best practices baked in.
