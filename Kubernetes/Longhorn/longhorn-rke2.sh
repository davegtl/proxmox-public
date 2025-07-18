#!/bin/bash

#############################################
# YOU SHOULD ONLY NEED TO EDIT THIS SECTION #
#############################################

# THIS SCRIPT IS FOR RKE2, NOT K3S!
# THIS SCRIPT IS FOR RKE2, NOT K3S!
# THIS SCRIPT IS FOR RKE2, NOT K3S!

# IP addresses of your Longhorn nodes
longhorn1=10.0.103.51
longhorn2=10.0.103.52
longhorn3=10.0.103.53

# Remote user
user=ubuntu

# Virtual IP of your RKE2 cluster (Kube-VIP)
vip=10.0.103.102

# SSH private key name (assumes ~/.ssh/<certName>)
certName=id_rsa

# Use DaveGTL’s customized Longhorn manifest with nodeSelectors preconfigured
longhorn_manifest="https://raw.githubusercontent.com/davegtl/proxmox-public/main/Kubernetes/RKE2/Longhorn/longhorn.yaml"

# Array of Longhorn node IPs
storage=($longhorn1 $longhorn2 $longhorn3)

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Check if all Longhorn nodes are reachable before continuing
echo -e "\n\033[34;5mChecking Longhorn node availability...\033[0m"
for node in "${storage[@]}"; do
  if ! ping -c 2 -W 1 $node &> /dev/null; then
    echo -e " \033[31;5mERROR: Node $node is not reachable. Exiting...\033[0m"
    exit 1
  else
    echo -e " \033[32;5mSUCCESS: Node $node is reachable.\033[0m"
  fi
done

# Start SSH agent and add private key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/$certName

# Sync time in case of snapshot time drift
sudo timedatectl set-ntp off
sudo timedatectl set-ntp on

# Check for RKE2 token file
if [ ! -f token ]; then
  echo -e " \033[31;5mERROR: token file not found in current directory.\033[0m"
  exit 1
fi
token=$(cat token)

# Copy SSH keys to Longhorn nodes
for node in "${storage[@]}"; do
  echo -e " \033[36;1mCopying SSH key to $node...\033[0m"
  ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/$certName $user@$node
done

# Ensure open-iscsi is installed locally
if ! dpkg -s open-iscsi &>/dev/null; then
  echo -e " \033[33;5mInstalling open-iscsi locally...\033[0m"
  sudo apt update && sudo apt install -y open-iscsi
else
  echo -e " \033[32;5mopen-iscsi already installed locally.\033[0m"
fi

# Join Longhorn nodes as RKE2 agents
for newnode in "${storage[@]}"; do
  echo -e " \033[36;1mSetting up RKE2 agent on $newnode...\033[0m"
  ssh -i ~/.ssh/$certName $user@$newnode <<EOF
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOT
token: ${token}
server: https://${vip}:9345
node-label:
  - longhorn=true
EOT
sudo curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service
EOF
  echo -e " \033[32;5mLonghorn node $newnode joined successfully!\033[0m"
done

# Wait for nodes to register
echo -e " \033[33;1mWaiting for Longhorn nodes to appear in the cluster...\033[0m"
sleep 20
kubectl get nodes -o wide

# Taint nodes to block regular workloads
echo -e " \033[33;1mTainting Longhorn nodes to prevent general workload scheduling...\033[0m"
for nodeip in "${storage[@]}"; do
  nodename=$(kubectl get nodes -o wide | grep "$nodeip" | awk '{print $1}')
  if [ -n "$nodename" ]; then
    kubectl taint nodes "$nodename" node.longhorn.io/create-default-disk=true:NoSchedule --overwrite
    echo -e " \033[32;1mTainted $nodename successfully.\033[0m"
  else
    echo -e " \033[31;1mFailed to find node for $nodeip — skipping taint.\033[0m"
  fi
done

# Install Longhorn
echo -e " \033[36;1mInstalling Longhorn using your custom manifest...\033[0m"
kubectl apply -f "$longhorn_manifest"

# Watch deployment progress
kubectl get pods -n longhorn-system --watch &
sleep 10

# Summary
echo -e "\n \033[32;1m=== Longhorn Installation Complete ===\033[0m"
kubectl get nodes
kubectl get svc -n longhorn-system

echo -e "\n \033[32;5mHappy Kubing! Longhorn v1.9.0 is now isolated to your dedicated nodes.\033[0m"
