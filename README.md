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

## Status

🚧 Work in progress — built incrementally, step by step, with full documentation
of each stage in `docs/`.

## Local Development

See `docs/environment-setup.md` for full RHEL 9.x environment bootstrap, and
`deploy/docker-compose/` for local Compose-based development.

## License

MIT
