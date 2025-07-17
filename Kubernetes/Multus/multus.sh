#!/bin/bash
set -euo pipefail

echo "📦 Deploying Multus CNI…"

# 0) Make sure namespace exists
kubectl get ns webservices >/dev/null 2>&1 || kubectl create ns webservices

# 1) Download VLAN50 network attachment definition
curl -sO https://raw.githubusercontent.com/davegtl/proxmox-public/main/Kubernetes/Multus/vlan50-net.yaml
curl -sO https://raw.githubusercontent.com/davegtl/proxmox-public/main/Kubernetes/Multus/vlan50-test.yaml

# 2) Apply Multus (thin plugin)
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml

# 3) Wait for rollout
kubectl -n kube-system rollout status daemonset/kube-multus-ds --timeout=2m

# 4) Apply your VLAN network definition
kubectl apply -f vlan50-net.yaml

# 5) Verify
kubectl get pods -n kube-system -l name=multus -o wide

echo "✅ Multus CNI is now installed and vlan50-net is configured!"
