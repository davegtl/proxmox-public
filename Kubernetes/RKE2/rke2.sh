#!/bin/bash

#############################################
# YOU SHOULD ONLY NEED TO EDIT THIS SECTION #
#############################################

# Version of Kube-VIP to deploy
KVVERSION="v0.9.2"

# Set the IP addresses of the admin, masters, and workers nodes
admin=10.0.103.5
master1=10.0.103.11
master2=10.0.103.12
master3=10.0.103.13
worker1=10.0.103.21
worker2=10.0.103.22

# User of remote machines
user=ubuntu

# Interface used on remotes
interface=eth0

# Set the virtual IP address (VIP)
vip=10.0.103.10

# Array of all master nodes
allmasters=($master1 $master2 $master3)

# Array of master nodes excluding master1 (for joining later)
masters=($master2 $master3)

# Array of worker nodes
workers=($worker1 $worker2)

# Array of all nodes
all=($master1 $master2 $master3 $worker1 $worker2)

# Loadbalancer IP range
lbrange=10.0.103.101-10.0.103.200

# SSH certificate name
certName=id_rsa

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Check if all nodes are reachable before continuing
echo -e "\033[34;5mChecking node availability...\033[0m"
check_nodes=($admin $master1 $master2 $master3 $worker1 $worker2)
for node in "${check_nodes[@]}"; do
  if ! ping -c 2 -W 1 $node &> /dev/null; then
    echo -e "\033[31;5mERROR: Node $node is not reachable. Exiting...\033[0m"
    exit 1
  else
    echo -e "\033[32;5mSUCCESS: Node $node is reachable.\033[0m"
  fi
done

echo -e "\033[34;5mAll nodes reachable. Continuing with installation...\033[0m"

# Start SSH agent and add key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/$certName

# For testing purposes - in case time is wrong due to VM snapshots
sudo timedatectl set-ntp off
sudo timedatectl set-ntp on

# Move SSH certs to ~/.ssh and change permissions
cp /home/$user/{$certName,$certName.pub} /home/$user/.ssh
chmod 600 /home/$user/.ssh/$certName 
chmod 644 /home/$user/.ssh/$certName.pub

# Install Kubectl if not already present
if ! command -v kubectl version &> /dev/null; then
  echo -e " \033[31;5mKubectl not found, installing\033[0m"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
  echo -e " \033[32;5mKubectl already installed\033[0m"
fi

# Create SSH config file to ignore host key checking (not recommended for production)
sed -i '1s/^/StrictHostKeyChecking no\n/' ~/.ssh/config

# Add SSH keys to all nodes
for node in "${all[@]}"; do
  ssh-copy-id $user@$node
done

# Step 1: Create Kube-VIP manifest
sudo mkdir -p /var/lib/rancher/rke2/server/manifests
curl -sO https://raw.githubusercontent.com/davegtl/proxmox-public/main/Kubernetes/RKE2/kube-vip
cat kube-vip | sed "s/\$interface/$interface/g; s/\$vip/$vip/g" > $HOME/kube-vip.yaml
sudo mv kube-vip.yaml /var/lib/rancher/rke2/server/manifests/kube-vip.yaml
sudo sed -i 's/k3s/rke2/g' /var/lib/rancher/rke2/server/manifests/kube-vip.yaml
sudo cp /var/lib/rancher/rke2/server/manifests/kube-vip.yaml ~/kube-vip.yaml
sudo chown $user:$user ~/kube-vip.yaml
mkdir -p ~/.kube

# Step 2: Create RKE2 config.yaml
mkdir -p ~/rke2tmp
cat <<EOF > ~/rke2tmp/config.yaml
tls-san:
  - $vip
  - $master1
  - $master2
  - $master3
write-kubeconfig-mode: 0644
disable:
  - rke2-ingress-nginx
EOF
sudo mkdir -p /etc/rancher/rke2
sudo cp ~/rke2tmp/config.yaml /etc/rancher/rke2/config.yaml

# Set up environment
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
echo 'export PATH=${PATH}:/var/lib/rancher/rke2/bin' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc

# Step 3: Copy kube-vip and config to all masters
for newnode in "${allmasters[@]}"; do
  scp -i ~/.ssh/$certName ~/kube-vip.yaml $user@$newnode:~/kube-vip.yaml
  scp -i ~/.ssh/$certName ~/rke2tmp/config.yaml $user@$newnode:~/config.yaml
  echo -e " \033[32;5mCopied config and kube-vip to $newnode\033[0m"
done

# Step 4: Install RKE2 on master1
ssh -i ~/.ssh/$certName $user@$master1 <<EOF
sudo mkdir -p /var/lib/rancher/rke2/server/manifests
sudo mv ~/kube-vip.yaml /var/lib/rancher/rke2/server/manifests/kube-vip.yaml
sudo mkdir -p /etc/rancher/rke2
sudo mv ~/config.yaml /etc/rancher/rke2/config.yaml
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
EOF

# Step 5: Fetch token and kubeconfig
ssh -i ~/.ssh/$certName $user@$master1 "sudo cat /var/lib/rancher/rke2/server/token" > ~/token
ssh -i ~/.ssh/$certName $user@$master1 "sudo cat /etc/rancher/rke2/rke2.yaml" > ~/.kube/rke2.yaml

# Step 6: Set up kubeconfig locally
export token=$(cat ~/token)
sed "s/127.0.0.1/$master1/g" ~/.kube/rke2.yaml > ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

# Step 7: Join other master nodes
for newnode in "${masters[@]}"; do
ssh -t -i ~/.ssh/$certName $user@$newnode "bash -s" <<EOF
set -eux
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOT
token: ${token}
server: https://${vip}:9345
node-label:
  - longhorn=true
EOT
curl -sfL https://get.rke2.io -o rke2-install.sh
chmod +x rke2-install.sh
sudo INSTALL_RKE2_TYPE="agent" ./rke2-install.sh
rm -f rke2-install.sh
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service
EOF

  echo -e " \033[32;5mMaster $newnode joined successfully!\033[0m"
done

kubectl get nodes

echo -e " \033[34;5mWaiting for kube-vip VIP at $vip to respond to Kubernetes API...\033[0m"

until curl -sk https://$vip:9345/version > /dev/null; do
  echo -e " \033[33;5mWaiting for VIP $vip to respond to /version...\033[0m"
  sleep 3
done

echo -e " \033[32;5mVIP is responding! Kubernetes API is ready at https://$vip:9345\033[0m"



for newnode in "${workers[@]}"; do
  ssh -i ~/.ssh/$certName $user@$newnode <<EOF
sudo mkdir -p /etc/rancher/rke2
cat <<EOL | sudo tee /etc/rancher/rke2/config.yaml
token: $token
server: https://$vip:9345
node-label:
  - worker=true
EOL
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service
EOF

  echo -e " \033[32;5mWorker $newnode joined successfully!\033[0m"

  host=$(ssh -i ~/.ssh/$certName $user@$newnode "hostname")
  echo -e " \033[34;5mWaiting for node $host to appear in the cluster...\033[0m"
  while ! kubectl get nodes | grep -q "$host"; do sleep 2; done
  echo -e " \033[32;5mNode $host successfully registered!\033[0m"
done

# Wait for all nodes to be Ready
echo -e " \033[34;5mWaiting for all nodes to be Ready...\033[0m"
until kubectl get nodes | grep -v "NotReady" | grep -q "Ready"; do
  kubectl get nodes
  sleep 3
done

# Wait for all pods in kube-system to be ready
echo -e " \033[34;5mWaiting for all kube-system pods to be ready...\033[0m"
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

echo -e " \033[32;5mAll nodes are Ready and all kube-system pods are running!\033[0m"

#PACKAGE MANAGER INSTALLATION
read -p "Do you want to install Rancher, MetalLB, and Cert-Manager? [y/N]: " install_rancher

if [[ "$install_rancher" =~ ^[Yy]$ ]]; then
  # Install Helm
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh

  # Add Rancher Helm Repo & create namespace
  helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
  kubectl create namespace cattle-system

  # Install MetalLB
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

  # Download ipAddressPool and configure using lbrange above
  curl -sO https://raw.githubusercontent.com/davegtl/proxmox-public/main/Kubernetes/RKE2/ipAddressPool
  cat ipAddressPool | sed 's/$lbrange/'$lbrange'/g' > $HOME/ipAddressPool.yaml

  # ✅ Wait for MetalLB controller to be ready
  kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=component=controller \
    --timeout=120s

  # ✅ Now apply the pool and l2Advertisement
  kubectl apply -f $HOME/ipAddressPool.yaml
  kubectl apply -f https://raw.githubusercontent.com/davegtl/proxmox-public/main/Kubernetes/RKE2/l2Advertisement.yaml

  kubectl get nodes
  kubectl get svc
  kubectl get pods --all-namespaces -o wide

  # Install Cert-Manager
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.14.4
  kubectl get pods --namespace cert-manager

  # Install Rancher
  helm install rancher rancher-latest/rancher \
    --namespace cattle-system \
    --set hostname=rancher.lan \
    --set bootstrapPassword=admin \
    --set service.type=LoadBalancer \
    --set service.loadBalancerIP=10.0.103.101
  kubectl -n cattle-system rollout status deploy/rancher
  kubectl -n cattle-system get deploy rancher

  # Wait for Rancher LoadBalancer to get an external IP
  echo -e " \033[32;5mWaiting for Rancher LoadBalancer to get an external IP...\033[0m"
  while [[ $(kubectl get svc rancher -n cattle-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}') == "" ]]; do
      sleep 5
      echo -e " \033[33mStill waiting...\033[0m"
  done
  echo -e " \033[32;5mRancher LoadBalancer is now available at IP: $(kubectl get svc rancher -n cattle-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\033[0m"

  kubectl get svc -n cattle-system

  echo -e " \033[32;5mAccess Rancher from the IP above - Password is admin!\033[0m"

  # Update Kube Config with VIP IP
  sudo sed "s/$master1/$vip/g" /etc/rancher/rke2/rke2.yaml | sudo tee /etc/rancher/rke2/rke2.yaml > /dev/null

else
  echo -e " \033[33mSkipping Rancher, MetalLB, and Cert-Manager installation.\033[0m"
fi
