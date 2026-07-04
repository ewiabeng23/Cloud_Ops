# Cirrus — End-to-End DevOps Project

This repository is the **workload** for a full, end-to-end DevOps project built by
our team. The application itself (a small finance app — FastAPI + a static glass
UI + a database) is deliberately kept simple: it exists so we have something real
to **containerize, provision infrastructure for, secure, deploy, and monitor**.

The point of this project is the **process and the toolchain**, not the app. By
the end we will have taken this code from a Git clone all the way to a running,
observable service on AWS, driven entirely by Infrastructure as Code and a CI/CD
pipeline.

> App details (how to run it locally, the API, etc.) live in [`README.app.md`](./README.app.md).
> This document is about **how we build and ship it as a team.**

---

## What we're building (the goal)

A complete DevOps lifecycle for one service:

**source control → secret scanning → containerization → CI/CD pipeline with
security gates → infrastructure as code on AWS → configuration management →
Kubernetes deployment → full monitoring stack.**

Every teammate should be able to stand up (and tear down) the whole stack from
this repo, and understand *why* each tool is in the chain.

---

## Versioning & a built-in learning exercise

- **v1 — "Cirrus".** The current app and stack. This is what we build first, end
  to end.
- **v2 — rebrand under a new name.** Once v1 is fully deployed and monitored, we
  roll out a **v2 with a different app name** as a deliberate exercise. A rename
  is not just a string change once the app is live — the name is threaded through
  the Docker image tag, the ECR repository, Kubernetes namespaces/labels, the
  Helm release, Prometheus scrape configs, Grafana dashboards, the CI/CD job, and
  (if used) the ArgoCD application. Doing the rename **through the pipeline, with
  no manual cluster edits and ideally no downtime** is the real test of whether
  our automation actually works. Treat v2 as the capstone.

To make v2 easier later: keep the app name driven from **config/variables** (Helm
values, Terraform vars, env) rather than hardcoded in many places.

---

## Target AWS architecture

Everything below is provisioned with **Terraform** (no clicking in the console).

```
                          Internet
                             |
                    +--------v---------+
                    | Internet Gateway |
                    +--------+---------+
   +======================== VPC (e.g. 10.0.0.0/16) ========================+
   |                                                                        |
   |  PUBLIC subnet tier  (internet-facing)                                 |
   |    - Application Load Balancer  <-- user traffic                       |
   |    - NAT Gateway  --> outbound-only internet for the private tier      |
   |              |                                                         |
   |  PRIVATE subnet tier  (no inbound from internet; outbound via NAT)     |
   |    - Kubernetes cluster (Kops on EC2) - Cirrus pods, deployed via Helm |
   |              |                    +------------+                       |
   |              |                                 v                       |
   |              |                        S3  (via Gateway VPC Endpoint)   |
   |              v                                                         |
   |  ISOLATED subnet tier  (no internet route at all)                      |
   |    - RDS PostgreSQL  <-- reachable only from the private tier on :5432 |
   +========================================================================+
```

**The three subnet tiers and why:**

| Tier | Contains | Internet access | Reason |
|------|----------|-----------------|--------|
| **Public** | ALB, NAT Gateway | Inbound + outbound | Only the load balancer and NAT should ever face the internet. |
| **Private** | Kubernetes (Kops) nodes / Cirrus pods | Outbound only (via NAT) | The app runs here; it can pull images/updates but can't be reached directly from outside. |
| **Isolated** | RDS PostgreSQL | None | The database must never touch the internet. It's only reachable from the private tier. |

Each tier is spread across **multiple Availability Zones** for high availability
(so in practice each "tier" is a set of subnets, one per AZ).

**S3 in the VPC:** S3 is a regional AWS service, so we reach it *privately* using
an **S3 Gateway VPC Endpoint** — traffic to buckets stays inside AWS's network and
never crosses the public internet. We use S3 for: **Terraform remote state**, the
**Kops cluster state store**, and general **object storage** for the project.

---

## Toolchain

| Tool | Category | Role here |
|------|----------|-----------|
| **Git + GitHub / GitLab** | Version control | Source of truth; triggers CI |
| **Gitleaks** | Secret scanning | Run **locally before every push** to catch secrets |
| **Docker** | Containerization | Package the app into an image |
| **Amazon ECR** | Image registry | Store built images for the cluster to pull |
| **Jenkins** *or* **GitLab CI** | CI/CD | Orchestrate the multi-stage pipeline |
| **SonarQube** | SAST | Static code analysis + quality gate |
| **Trivy** | Image / IaC scanning | Scan the container image (and configs) for CVEs |
| **Checkov** | IaC scanning | Scan Terraform & Helm for misconfigurations |
| **OWASP ZAP** | DAST | Scan the running app (post-deploy) |
| **Terraform** | Infrastructure as Code | Provision **all** AWS infra |
| **Ansible** | Configuration management | Configure servers & tooling (e.g. the CI server) |
| **Kops** | K8s provisioning | Self-managed Kubernetes cluster on EC2 |
| **Helm** | K8s packaging | Template & deploy the app to the cluster |
| **ArgoCD** *(optional)* | GitOps | Declarative, git-driven deployments |
| **Prometheus** | Monitoring | Scrape metrics from the app's `/metrics` |
| **Grafana** | Monitoring | Dashboards & visualization |
| **AWS** (VPC, EC2, RDS, S3, ELB, NAT) | Cloud | Where it all runs |

---

## Prerequisites (each teammate installs)

- An **AWS account** with the **AWS CLI** configured (`aws configure`)
- **Terraform**, **Ansible**, **kubectl**, **kops**, **helm**
- **Docker** (Docker Desktop on Mac/Windows)
- **Gitleaks** and **Trivy** locally (for pre-push / local scans)
- **Git**, and a **GitHub or GitLab** account
- Agree as a team on: **AWS region**, VPC CIDR, cluster name, and whether infra
  lives in **this repo** or a **separate infra repo** (recommended: separate).

---

## The process (end-to-end workflow)

Follow these phases in order. Steps 0–1 are per-person; the rest are done once for
the shared environment (coordinate so you're not provisioning duplicates).

### 0. Clone

```bash
git clone <this-repo-url>
cd cirrus
```

### 1. Secret scan, then push to our repo

**Before pushing anywhere**, scan for secrets. Never push code that trips Gitleaks.

```bash
gitleaks detect --source . --redact --verbose
```

If it's clean, push to the team's repo (or your fork):

```bash
git remote set-url origin <team-repo-url>   # or add a new remote
git push
```

> Make this a habit / pre-commit hook. Catching a leaked credential locally is
> free; catching it after it's in git history is painful.

### 2. Provision the AWS infrastructure (Terraform)

All infra is codified. Terraform builds the **VPC + 3 subnet tiers, NAT, IGW, the
S3 buckets + Gateway Endpoint, RDS PostgreSQL (isolated tier), ECR,** and IAM.

```bash
cd infra/terraform          # (to be added)
terraform init
terraform plan  -out=plan.out
terraform apply plan.out
```

Before applying, run the IaC security scan:

```bash
checkov -d infra/terraform
```

Terraform **outputs** the values later stages need: RDS endpoint, ECR URL, S3
bucket names, VPC/subnet IDs, Kops state store.

### 3. Configure with Ansible

Terraform builds the boxes; **Ansible configures them** — e.g. installs and
configures the **CI server (Jenkins)** and the toolchain (Docker, Trivy, kubectl,
helm, kops, Sonar scanner).

```bash
cd infra/ansible            # (to be added)
ansible-playbook -i inventory site.yml
```

### 4. Stand up Kubernetes (Kops) in the private tier

Kops provisions a self-managed cluster on EC2 inside the **private** subnets,
using the **S3 state store** Terraform created.

```bash
export KOPS_STATE_STORE=s3://<kops-state-bucket>
kops create cluster ...        # (commands to be added)
kops update cluster --yes
kops validate cluster --wait 10m
```

### 5. CI/CD pipeline (Jenkins or GitLab)

A push to the repo triggers a pipeline with these **stages**:

1. **Checkout**
2. **Gitleaks** — secret scan
3. **Build & unit test**
4. **SonarQube (SAST)** + **quality gate** (fail the build if it doesn't pass)
5. **Checkov** — scan Terraform / Helm
6. **Docker build**
7. **Trivy** — scan the image; fail on HIGH/CRITICAL
8. **Push image to ECR**
9. **Deploy to Kubernetes with Helm** (or, with GitOps, commit the new image tag
   and let **ArgoCD** sync it)
10. **OWASP ZAP (DAST)** — scan the running app

> Jenkins: pipeline defined in a `Jenkinsfile`.
> GitLab CI: pipeline defined in `.gitlab-ci.yml`.
> Pick one as a team; the stage logic is the same.

### 6. Deploy the app (Helm)

The app is packaged as a Helm chart. Deployment injects config as env vars —
crucially the **database connection** (see RDS below) and the app image tag.

```bash
helm upgrade --install cirrus ./deploy/helm/cirrus \
  --namespace cirrus --create-namespace \
  -f values.prod.yaml
```

### 7. Monitoring (Prometheus + Grafana)

Install the monitoring stack into the cluster (e.g. the `kube-prometheus-stack`
Helm chart). The app already exposes Prometheus metrics at **`/metrics`**;
Prometheus scrapes it and Grafana dashboards visualize request rate, latency,
errors, and DB/runtime health.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### 8. (Optional) GitOps with ArgoCD

Instead of the pipeline running `helm upgrade` against the cluster, the pipeline
commits the new image tag to a **GitOps repo**, and **ArgoCD** continuously
reconciles the cluster to match git. Git becomes the single source of truth and a
rollback is just a `git revert`.

---

## How the database (RDS) fits

The app is **database-agnostic**: it reads its connection string from the
`DATABASE_URL` environment variable and uses SQLAlchemy, which speaks plain
PostgreSQL. So moving from local dev to AWS is a **config change, not a code
change**:

- **Local:** `DATABASE_URL` unset → app falls back to SQLite (a file). Zero setup.
- **AWS:** `DATABASE_URL=postgresql+psycopg2://<user>:<pass>@<rds-endpoint>:5432/cirrus`
  → app talks to RDS. The schema is created on first start.

Key points for how we run RDS in this project:

- **RDS is managed PostgreSQL.** AWS runs the DB server, backups, and patching; we
  just get a connection **endpoint**. Terraform provisions the instance.
- **It lives in the ISOLATED subnet tier** — **not publicly accessible**. Only the
  Kubernetes nodes in the private tier can reach it, via a security group allowing
  TCP **5432** from the app's security group.
- **Credentials are secrets.** The DB username/password are **never** committed.
  They're passed to Terraform via a variable (from an env var / secrets manager)
  and injected into the app as a **Kubernetes Secret → `DATABASE_URL` env var**.
  (Gitleaks in step 1 is our safety net against leaking them.)
- **Migrations:** v1 uses SQLAlchemy `create_all()` on startup, which is fine for
  now. For production-grade schema management we'll move to **Alembic** so schema
  changes are versioned. (Good task for a later iteration.)
- **Cost:** RDS bills **per hour, 24/7**, whether or not the app is busy. Use the
  smallest instance (`db.t3.micro`, single-AZ) for learning, and **destroy the
  stack when not in use.**

---

## Cost & teardown (read this)

This stack costs real money — EC2 (Kops control plane + nodes), RDS, NAT Gateway,
and load balancers all bill hourly. **Tear everything down when you're done for
the day:**

```bash
kops delete cluster --name <cluster> --yes
cd infra/terraform && terraform destroy
```

Coordinate as a team so one person doesn't destroy shared infra another is using.

---

## Repo conventions

- **Never commit secrets.** Run Gitleaks before pushing; keep credentials in env
  vars / a secrets manager / Kubernetes Secrets.
- **Infra is code.** No manual changes in the AWS console or `kubectl edit` on the
  cluster — change the Terraform/Helm/manifests and let the pipeline apply them.
- **Branch + PR** for changes; let CI run before merge.
- Keep the app **name and environment-specific values in variables**, not
  hardcoded — this is what makes the v2 rename painless.

---

## Status / roadmap

- [x] App (v1: Cirrus) — containerizable, DB-agnostic, exposes `/health` + `/metrics`
- [ ] Terraform: VPC (3 tiers), NAT/IGW, S3 + endpoint, RDS, ECR, IAM
- [ ] Ansible: CI server + toolchain configuration
- [ ] Kops cluster in the private tier
- [ ] CI/CD pipeline (Jenkins **or** GitLab) with security gates
- [ ] Helm deployment
- [ ] Prometheus + Grafana monitoring
- [ ] (Optional) ArgoCD GitOps
- [ ] v2 rebrand rolled out through the pipeline
