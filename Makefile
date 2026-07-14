# ============================
# Docker Compose (Chapter 2)
# ============================
COMPOSE_DIR = deploy/docker-compose

.PHONY: compose-up compose-down compose-logs compose-ps

compose-up:
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml --env-file $(COMPOSE_DIR)/.env up --build -d

compose-down:
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml down -v

compose-logs:
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml logs -f

compose-ps:
	docker compose -f $(COMPOSE_DIR)/docker-compose.yaml ps

# ============================
# Kind Cluster (Chapter 3)
# ============================
KIND_CONFIG = scripts/kind-cluster-config.yaml
CALICO_VERSION = v3.28.0

.PHONY: cluster-up cluster-down cluster-status

cluster-up:
	kind create cluster --config $(KIND_CONFIG)
	kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$(CALICO_VERSION)/manifests/tigera-operator.yaml
	kubectl apply -f deploy/k8s/base/calico-installation.yaml
	@echo "Waiting for Calico to become ready (this can take 1-3 minutes)..."
	kubectl -n calico-system wait --for=condition=Ready pods --all --timeout=300s

cluster-down:
	kind delete cluster --name platform

cluster-status:
	kubectl get nodes -o wide
	kubectl get pods -n calico-system

# ============================
# auth-service (Chapter 4)
# ============================
.PHONY: build-auth load-auth deploy-auth logs-auth

build-auth:
	docker build -t platform/auth-service:local ./apps/auth-service

load-auth: build-auth
	kind load docker-image platform/auth-service:local --name platform

deploy-auth: load-auth
	kubectl apply -f deploy/k8s/base/namespaces/platform-namespace.yaml
	kubectl apply -f deploy/k8s/base/postgres/deployment.yaml
	kubectl apply -f deploy/k8s/base/postgres/service.yaml
	kubectl apply -f deploy/k8s/base/auth-service/deployment.yaml
	kubectl apply -f deploy/k8s/base/auth-service/service.yaml
	kubectl rollout status deployment/auth-service -n platform

logs-auth:
	kubectl logs -n platform -l app=auth-service -f --prefix
# ============================
# (Chapter 5)
# ============================

.PHONY: build-all load-all deploy-all status

build-all:
	docker build -t platform/backend:local ./apps/backend
	docker build -t platform/auth-service:local ./apps/auth-service
	docker build -t platform/notification-service:local ./apps/notification-service
	docker build -t platform/frontend:local ./apps/frontend

load-all: build-all
	kind load docker-image platform/backend:local --name platform
	kind load docker-image platform/auth-service:local --name platform
	kind load docker-image platform/notification-service:local --name platform
	kind load docker-image platform/frontend:local --name platform

deploy-all: load-all
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

status:
	kubectl get deployments,pods,svc -n platform
# ============================
# (Chapter 6)
# ============================

.PHONY: deploy-postgres

deploy-postgres:
	kubectl apply -f deploy/k8s/base/postgres/headless-service.yaml
	kubectl apply -f deploy/k8s/base/postgres/service.yaml
	kubectl apply -f deploy/k8s/base/postgres/statefulset.yaml
	kubectl rollout status statefulset/postgres -n platform

# ============================
# (Chapter 7)
# ============================

.PHONY: create-secrets apply-config

create-secrets:
	./scripts/create-secrets.sh

apply-config:
	kubectl apply -f deploy/k8s/base/backend/configmap.yaml
	kubectl apply -f deploy/k8s/base/auth-service/configmap.yaml
	kubectl apply -f deploy/k8s/base/notification-service/configmap.yaml
	kubectl apply -f deploy/k8s/base/frontend/configmap.yaml
	kubectl apply -f deploy/k8s/base/postgres/configmap.yaml

# ============================
# (Chapter 8)
# ============================


.PHONY: install-ingress deploy-ingress hosts-entry

install-ingress:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml
	kubectl -n ingress-nginx wait --for=condition=Ready pods -l app.kubernetes.io/component=controller --timeout=180s

deploy-ingress:
	kubectl apply -f deploy/k8s/base/ingress/platform-ingress.yaml

hosts-entry:
	@grep -q "platform.local" /etc/hosts || echo "127.0.0.1 platform.local" | sudo tee -a /etc/hosts

# ============================
# (Chapter 9)
# ============================

.PHONY: deploy-cronjob trigger-cleanup

deploy-cronjob:
	kubectl apply -f deploy/k8s/base/auth-service/cleanup-cronjob.yaml

trigger-cleanup:
	kubectl create job users-cleanup-$$(date +%s) --from=cronjob/users-cleanup -n platform

# ============================
# (Chapter 10)
# ============================

.PHONY: check-probes demo-selfheal

check-probes:
	kubectl describe pod -n platform -l app=auth-service | grep -A 3 "Liveness\|Readiness\|Startup"

demo-selfheal:
	@echo "Scaling postgres to 0 to demonstrate readiness failure without restart..."
	kubectl scale statefulset postgres -n platform --replicas=0
	@echo "Watch: kubectl get endpoints auth-service -n platform -w"
	@echo "Run 'make restore-postgres' when done observing."

restore-postgres:
	kubectl scale statefulset postgres -n platform --replicas=1
	kubectl wait --for=condition=Ready pod postgres-0 -n platform --timeout=60s

# ============================
# (Chapter 11)
# ============================


.PHONY: check-qos check-pdb drain-test

check-qos:
	kubectl get pods -n platform -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

check-pdb:
	kubectl get pdb -n platform

drain-test:
	@echo "Usage: kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --timeout=120s"
	@echo "Then: kubectl uncordon <node-name>"

# ============================
# (Chapter 12)
# ============================


.PHONY: install-metrics-server check-hpa load-test stop-load-test

install-metrics-server:
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl patch deployment metrics-server -n kube-system --type='json' \
		-p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
	kubectl rollout status deployment/metrics-server -n kube-system

check-hpa:
	kubectl get hpa -n platform
	kubectl top pods -n platform

load-test:
	kubectl run load-generator -n platform --image=busybox:1.36 --restart=Never -- \
		sh -c "while true; do wget -q -O- --post-data='{\"username\":\"load-test\"}' --header='Content-Type: application/json' http://backend:4000/login; done"

stop-load-test:
	kubectl delete pod load-generator -n platform --ignore-not-found

# ============================
# (Chapter 13)
# ============================

.PHONY: apply-netpol test-netpol-allowed test-netpol-blocked

apply-netpol:
	kubectl apply -f deploy/k8s/base/network-policies/allow-dns.yaml
	kubectl apply -f deploy/k8s/base/network-policies/auth-service-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/backend-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/postgres-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/redis-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/rabbitmq-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/notification-service-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/frontend-netpol.yaml
	kubectl apply -f deploy/k8s/base/network-policies/default-deny-all.yaml

test-netpol-allowed:
	curl -X POST http://platform.local/api/login -H "Content-Type: application/json" -d '{"username":"netpol-verify"}'

test-netpol-blocked:
	kubectl run netpol-attacker -n platform --image=busybox:1.36 --restart=Never --labels="app=frontend" -- sleep 60
	@sleep 3
	kubectl exec -n platform netpol-attacker -- timeout 3 nc -zv postgres 5432 || echo "Correctly blocked."
	kubectl delete pod netpol-attacker -n platform --ignore-not-found

# ============================
# (Chapter 14)
# ============================


.PHONY: deploy-fluentbit check-fluentbit

deploy-fluentbit:
	kubectl apply -f deploy/k8s/base/fluent-bit/rbac.yaml
	kubectl apply -f deploy/k8s/base/fluent-bit/configmap.yaml
	kubectl apply -f deploy/k8s/base/fluent-bit/daemonset.yaml
	kubectl rollout status daemonset/fluent-bit -n platform

check-fluentbit:
	kubectl get pods -n platform -l app=fluent-bit -o wide
	kubectl get daemonset fluent-bit -n platform

# ============================
# (Chapter 15)
# ============================


.PHONY: install-monitoring grafana-ui check-monitoring

install-monitoring:
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

grafana-ui:
	kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3001:80

check-monitoring:
	kubectl get pods -n observability
	kubectl top nodes
	kubectl top pods -n observability
