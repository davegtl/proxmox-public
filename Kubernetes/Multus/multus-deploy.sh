#!/bin/bash
set -euo pipefail

echo "📦 Deploying Multus CNI…"

# 1) Apply the official k8snetworkplumbingwg Multus DaemonSet
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/images/multus-daemonset.yml

# 2) Wait for it to roll out
kubectl -n kube-system rollout status daemonset/kube-multus-ds --timeout=2m

# 3) Verify one pod per node
kubectl get pods -n kube-system -l name=multus -o wide

echo "✅ Multus CNI is now installed!"
