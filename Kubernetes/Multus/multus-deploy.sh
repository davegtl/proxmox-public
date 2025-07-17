# 1. Add the RKE2 charts repo
helm repo add rke2-charts https://rke2-charts.rancher.io
helm repo update

# 2. Ensure the kube-system ns exists
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -

# 3. Deploy Multus
cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: multus
  namespace: kube-system
spec:
  repo: https://rke2-charts.rancher.io
  chart: rke2-multus
  targetNamespace: kube-system
  valuesContent: |
    config:
      fullnameOverride: multus
      cni_conf:
        confDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
        binDir:  /var/lib/rancher/k3s/data/cni
EOF

# 4. Verify
kubectl -n kube-system rollout status daemonset/multus
echo -e " \033[32;5mMultus deployed successfully!\033[0m"
