.PHONY: help
help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

# ============================
# Local development: Docker Compose
# ============================
COMPOSE_DIR = deploy/docker-compose

.PHONY: compose-up compose-down compose-logs compose-ps

compose-up: ## Start the full stack locally via Docker Compose
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml --env-file $(COMPOSE_DIR)/.env up --build -d

compose-down: ## Stop and remove the Compose stack
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml down -v

compose-logs: ## Tail logs from the Compose stack
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml logs -f

compose-ps: ## Show Compose service status
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml ps

# ============================
# Kubernetes cluster bootstrap
# ============================
KIND_CONFIG = scripts/kind-cluster-config.yaml
CALICO_VERSION = v3.28.0

.PHONY: cluster-up cluster-down cluster-status

cluster-up: ## Create the Kind cluster and install Calico
	kind create cluster --config $(KIND_CONFIG)
	kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$(CALICO_VERSION)/manifests/tigera-operator.yaml
	kubectl apply -f deploy/k8s/base/calico-installation.yaml
	@echo "Waiting for Calico to become ready (this can take 1-3 minutes)..."
	kubectl -n calico-system wait --for=condition=Ready pods --all --timeout=300s

cluster-down: ## Delete the Kind cluster
	kind delete cluster --name platform

cluster-status: ## Show node and Calico pod status
	kubectl get nodes -o wide
	kubectl get pods -n calico-system

# ============================
# auth-service logs
# ============================
.PHONY: logs-auth

logs-auth: ## Tail auth-service logs
	kubectl logs -n platform -l app=auth-service -f --prefix

# ============================
# Application services: build, load, deploy
# ============================
.PHONY: build-all load-all deploy-all status

build-all: ## Build all four application images
	docker build -t platform/backend:local ./apps/backend
	docker build -t platform/auth-service:local ./apps/auth-service
	docker build -t platform/notification-service:local ./apps/notification-service
	docker build -t platform/frontend:local ./apps/frontend

load-all: build-all ## Build and load all images into Kind
	kind load docker-image platform/backend:local --name platform
	kind load docker-image platform/auth-service:local --name platform
	kind load docker-image platform/notification-service:local --name platform
	kind load docker-image platform/frontend:local --name platform

deploy-all: load-all ## Deploy the full application stack
	kubectl apply -f deploy/k8s/base/namespaces/platform-namespace.yaml
	kubectl apply -f deploy/k8s/base/postgres/
	kubectl apply -f deploy/k8s/base/auth-service/
	kubectl apply -f deploy/k8s/base/redis/
	kubectl apply -f deploy/k8s/base/rabbitmq/
	kubectl apply -f deploy/k8s/base/backend/
	kubectl apply -f deploy/k8s/base/notification-service/
	kubectl apply -f deploy/k8s/base/frontend/
	kubectl rollout status deployment/auth-service -n platform
	kubectl rollout status deployment/backend -n platform
	kubectl rollout status deployment/notification-service -n platform
	kubectl rollout status deployment/frontend -n platform

status: ## Show deployments, pods, and services
	kubectl get deployments,pods,svc -n platform

# ============================
# StatefulSet: PostgreSQL
# ============================
.PHONY: deploy-postgres restore-postgres

deploy-postgres: ## Deploy Postgres StatefulSet + services
	kubectl apply -f deploy/k8s/base/postgres/headless-service.yaml
	kubectl apply -f deploy/k8s/base/postgres/service.yaml
	kubectl apply -f deploy/k8s/base/postgres/statefulset.yaml
	kubectl rollout status statefulset/postgres -n platform

restore-postgres: ## Scale Postgres back to 1 replica after demo-selfheal
	kubectl scale statefulset postgres -n platform --replicas=1
	kubectl wait --for=condition=Ready pod postgres-0 -n platform --timeout=60s

# ============================
# Secrets and ConfigMaps
# ============================
.PHONY: create-secrets apply-config

create-secrets: ## Create Kubernetes secrets
	./scripts/create-secrets.sh

apply-config: ## Apply all ConfigMaps
	kubectl apply -f deploy/k8s/base/backend/configmap.yaml
	kubectl apply -f deploy/k8s/base/auth-service/configmap.yaml
	kubectl apply -f deploy/k8s/base/notification-service/configmap.yaml
	kubectl apply -f deploy/k8s/base/frontend/configmap.yaml
	kubectl apply -f deploy/k8s/base/postgres/configmap.yaml

# ============================
# Ingress
# ============================
.PHONY: install-ingress deploy-ingress hosts-entry

install-ingress: ## Install the NGINX ingress controller
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml
	kubectl -n ingress-nginx wait --for=condition=Ready pods -l app.kubernetes.io/component=controller --timeout=180s

deploy-ingress: ## Apply the platform Ingress resource
	kubectl apply -f deploy/k8s/base/ingress/platform-ingress.yaml

hosts-entry: ## Add platform.local to /etc/hosts
	@grep -q "platform.local" /etc/hosts || echo "127.0.0.1 platform.local" | sudo tee -a /etc/hosts

# ============================
# CronJobs
# ============================
.PHONY: deploy-cronjob trigger-cleanup

deploy-cronjob: ## Deploy the users-cleanup CronJob
	kubectl apply -f deploy/k8s/base/auth-service/cleanup-cronjob.yaml

trigger-cleanup: ## Manually trigger the cleanup CronJob
	kubectl create job users-cleanup-$$(date +%s) --from=cronjob/users-cleanup -n platform

# ============================
# Health probes and self-healing
# ============================
.PHONY: check-probes demo-selfheal

check-probes: ## Show liveness/readiness/startup probe status
	kubectl describe pod -n platform -l app=auth-service | grep -A 3 "Liveness\|Readiness\|Startup"

demo-selfheal: ## Scale Postgres to 0 to demonstrate readiness failure
	@echo "Scaling postgres to 0 to demonstrate readiness failure without restart..."
	kubectl scale statefulset postgres -n platform --replicas=0
	@echo "Watch: kubectl get endpoints auth-service -n platform -w"
	@echo "Run 'make restore-postgres' when done observing."

# ============================
# Resource QoS and PodDisruptionBudgets
# ============================
.PHONY: check-qos check-pdb drain-test

check-qos: ## Show QoS class per pod
	kubectl get pods -n platform -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

check-pdb: ## Show PodDisruptionBudget status
	kubectl get pdb -n platform

drain-test: ## Print the commands to test node draining
	@echo "Usage: kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --timeout=120s"
	@echo "Then: kubectl uncordon <node-name>"

# ============================
# Autoscaling (HPA) and load testing
# ============================
.PHONY: install-metrics-server check-hpa load-test stop-load-test

install-metrics-server: ## Install and patch the Metrics Server
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl patch deployment metrics-server -n kube-system --type='json' \
		-p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
	kubectl rollout status deployment/metrics-server -n kube-system

check-hpa: ## Show HPA status and pod resource usage
	kubectl get hpa -n platform
	kubectl top pods -n platform

load-test: ## Generate load against the backend to trigger HPA
	kubectl run load-generator -n platform --image=busybox:1.36 --restart=Never -- \
		sh -c "while true; do wget -q -O- --post-data='{\"username\":\"load-test\"}' --header='Content-Type: application/json' http://backend:4000/login; done"

stop-load-test: ## Stop the load generator pod
	kubectl delete pod load-generator -n platform --ignore-not-found

# ============================
# NetworkPolicies (zero-trust networking)
# ============================
.PHONY: apply-netpol test-netpol-allowed test-netpol-blocked

apply-netpol: ## Apply all NetworkPolicies
	kubectl apply -f deploy/k8s/base/network-policies/allow-dns.yaml
	kubectl apply -f deploy/k8s/base/network-policies/auth-service-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/backend-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/postgres-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/redis-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/rabbitmq-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/notification-service-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/frontend-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/default-deny-all.yaml

test-netpol-allowed: ## Prove the normal login path still works
	curl -X POST http://platform.local/api/login -H "Content-Type: application/json" -d '{"username":"netpol-verify"}'

test-netpol-blocked: ## Prove frontend cannot reach Postgres directly
	kubectl run netpol-attacker -n platform --image=busybox:1.36 --restart=Never --labels="app=frontend" -- sleep 60
	@sleep 3
	kubectl exec -n platform netpol-attacker -- timeout 3 nc -zv postgres 5432 || echo "Correctly blocked."
	kubectl delete pod netpol-attacker -n platform --ignore-not-found

# ============================
# Logging: Fluent Bit
# ============================
.PHONY: deploy-fluentbit check-fluentbit

deploy-fluentbit: ## Deploy Fluent Bit log collection
	kubectl apply -f deploy/k8s/base/fluent-bit/rbac.yaml
	kubectl apply -f deploy/k8s/base/fluent-bit/configmap.yaml
	kubectl apply -f deploy/k8s/base/fluent-bit/daemonset.yaml
	kubectl rollout status daemonset/fluent-bit -n platform

check-fluentbit: ## Show Fluent Bit pod status
	kubectl get pods -n platform -l app=fluent-bit -o wide
	kubectl get daemonset fluent-bit -n platform

# ============================
# Observability: Prometheus, Grafana, Loki
# ============================
.PHONY: install-monitoring grafana-ui check-monitoring

install-monitoring: ## Install Prometheus, Grafana, Loki
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
	helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace observability \
		--values deploy/k8s/base/observability/prometheus-values.yaml \
		--timeout 10m
	helm install loki grafana/loki-stack \
		--namespace observability \
		--values deploy/k8s/base/observability/loki-values.yaml \
		--timeout 5m

grafana-ui: ## Port-forward the Grafana UI (localhost:3001)
	kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3001:80

check-monitoring: ## Show observability stack status and resource usage
	kubectl get pods -n observability
	kubectl top nodes
	kubectl top pods -n observability

# ============================
# Packaging: Helm
# ============================
.PHONY: helm-lint helm-template helm-install helm-upgrade helm-rollback helm-status

helm-lint: ## Lint the Helm chart
	cd deploy/helm/platform && helm lint .

helm-template: ## Render the Helm chart locally
	cd deploy/helm/platform && helm template platform . --values values.yaml

helm-install: ## Install the platform via Helm
	cd deploy/helm/platform && helm install platform . --values values.yaml --namespace platform

helm-upgrade: ## Upgrade the platform via Helm
	cd deploy/helm/platform && helm upgrade platform . --values values.yaml --namespace platform

helm-status: ## Show Helm release status and history
	helm status platform -n platform
	helm history platform -n platform

# ============================
# GitOps: ArgoCD
# ============================
.PHONY: install-argocd apply-argocd-app argocd-ui argocd-status

install-argocd: ## Install ArgoCD into the argocd namespace
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
	kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

apply-argocd-app: ## Register the platform Application with ArgoCD
	kubectl apply -f gitops/argocd/platform-app.yaml

argocd-ui: ## Port-forward the ArgoCD UI (https://localhost:8080)
	kubectl port-forward -n argocd svc/argocd-server 8080:443

argocd-status: ## Show ArgoCD application sync status
	kubectl get application platform -n argocd

# ============================
# Full rebuild
# ============================
.PHONY: rebuild

rebuild: cluster-down cluster-up create-secrets deploy-postgres deploy-all install-ingress deploy-ingress apply-netpol deploy-fluentbit install-metrics-server helm-install install-argocd apply-argocd-app ## Full clean rebuild from scratch
	@echo ""
	@echo "Rebuild complete. Run 'make status' and 'make argocd-status' to verify."
