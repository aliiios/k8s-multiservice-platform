# Kubernetes Multi-Service Platform

A production-style, Kubernetes-native multi-service platform built to master
Cloud Native concepts: containerization, orchestration, networking, security,
observability, and GitOps — from a local Kind cluster to a full ArgoCD-driven
deployment pipeline.

> This project intentionally keeps application logic minimal. The goal is
> depth in Kubernetes and Cloud Native engineering, not application features.

## Architecture
- **Frontend** — thin UI client
- **Backend** — core API service
- **Auth Service** — authentication/token issuance
- **Notification Service** — async notification worker
- **PostgreSQL** — primary relational data store
- **Redis** — caching / session store
- **RabbitMQ** — async messaging between services


How a request flows through the platform
<img width="1100" height="980" alt="How a request flows through the platform" src="https://github.com/user-attachments/assets/890783b9-8742-4bea-be19-b6b8831d2e46" />


GitOps delivery & platform operations
<img width="1104" height="1062" alt="GitOps delivery   platform operations" src="https://github.com/user-attachments/assets/c4fd177f-45b7-43ed-a152-6b05ed1216f0" />


Kubernetes Cluster — Internal Architecture
<img width="1441" height="1296" alt="Kubernetes Cluster — Internal Architecture" src="https://github.com/user-attachments/assets/2cca7b26-5f8b-47dd-a97d-7c2cab3316a6" />


## Stack

| Layer | Technology |
|---|---|
| Orchestration | Kubernetes (Kind), Calico CNI |
| Packaging | Helm |
| GitOps | ArgoCD |
| Services | Node.js / Express (7 microservices) |
| Data | PostgreSQL (StatefulSet), Redis, RabbitMQ |
| Observability | Prometheus, Grafana, Loki, Fluent Bit |
| Security | NetworkPolicies (zero-trust), RBAC, non-root containers |

## What this demonstrates

- Deployment/StatefulSet/Service object modeling
- Helm chart authoring with templated multi-service loops
- GitOps continuous delivery (git push → auto-deploy)
- Zero-trust NetworkPolicies (default-deny + least privilege)
- HPA autoscaling, PodDisruptionBudgets, resource QoS
- Full observability (metrics, logs, dashboards)

## Problems solved

This project includes real debugging, not just a happy-path tutorial — see 
[troubleshooting-log.docx](link) for the full incident log. Highlights:

- Diagnosed and fixed a Helm templating bug that silently dropped Kubernetes objects
- Isolated a Docker-in-Docker CNI hostPort defect through systematic testing
- Tuned health probes (RabbitMQ, Grafana) that were killing healthy pods under load

## Status

🚧 Work in progress — built incrementally, step by step, with full documentation
of each stage in `docs/`.

## Local Development

See `docs/environment-setup.md` for full RHEL 9.x environment bootstrap, and
`deploy/docker-compose/` for local Compose-based development.
