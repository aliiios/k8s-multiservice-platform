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
