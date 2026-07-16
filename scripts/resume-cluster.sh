#!/usr/bin/env bash
set -e

echo "== Ensuring Docker is running =="
sudo systemctl start docker

echo "== Starting Kind node containers =="
docker start platform-control-plane platform-worker platform-worker2

echo "== Waiting for nodes to settle =="
sleep 15

NOT_READY=$(kubectl get nodes --no-headers | awk '$2 != "Ready" {print $1}')
if [ -n "$NOT_READY" ]; then
  echo "== Restarting unhealthy node containers: $NOT_READY =="
  for node in $NOT_READY; do
    docker restart "$node"
  done
  sleep 20
fi

echo "== Node status =="
kubectl get nodes

echo "== CoreDNS status =="
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

echo "== Calico status =="
kubectl get pods -n calico-system -o wide

echo "== fluent-bit status =="
kubectl get pods -n platform -l app=fluent-bit -o wide
