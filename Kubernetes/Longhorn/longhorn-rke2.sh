#!/bin/bash

echo -e " \033[33;2m    __  _          _        ___                            \033[0m"
echo -e " \033[33;2m    \\ \\(_)_ __ ___( )__    / _ \\__ _ _ __ __ _  __ _  ___  \033[0m"
echo -e " \033[33;2m     \\ \\ | '_ \` _ \\/ __|  / /_\\/ _\` | '__/ _\` |/ _\` |/ _ \\ \033[0m"
echo -e " \033[33;2m  /\\_/ / | | | | | \\__ \\ / /_\\\\ (_| | | | (_| | (_| |  __/ \033[0m"
echo -e " \033[33;2m  \\___/|_|_| |_| |_|___/ \\____/\\__,_|_|  \\__,_|\\__, |\\___| \033[0m"
echo -e " \033[33;2m                                               |___/       \033[0m"
echo -e " \033[35;2m          __                   _                          \033[0m"
echo -e " \033[35;2m         / /  ___  _ __   __ _| |__   ___  _ __ _ __      \033[0m"
echo -e " \033[35;2m        / /  / _ \\| '_ \\ / _\` | '_ \\ / _ \\| '__| '_ \\     \033[0m"
echo -e " \033[35;2m       / /__| (_) | | | | (_| | | | | (_) | |  | | | |    \033[0m"
echo -e " \033[35;2m       \\____/\\___/|_| |_|\\__, |_| |_|\\___/|_|  |_| |_|    \033[0m"
echo -e " \033[35;2m                         |___/                            \033[0m"
echo -e " \033[36;2m                                                          \033[0m"
echo -e " \033[32;2m             https://youtube.com/@jims-garage              \033[0m"
echo -e " \033[32;2m                                                           \033[0m"

#############################################
# YOU SHOULD ONLY NEED TO EDIT THIS SECTION #
#############################################

# Set the IP addresses of your Longhorn nodes
longhorn1=10.0.103.51
longhorn2=10.0.103.52
longhorn3=10.0.103.53

# User of remote machines
user=ubuntu

# Interface used on remotes
interface=eth0

# Set the virtual IP address (VIP)
vip=10.0.103.10

# Array of longhorn nodes
storage=($longhorn1 $longhorn2 $longhorn3)

# SSH private key name
certName=id_rsa

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Sync time (useful after snapshot restores)
sudo timedatectl set-ntp off
sudo timedatectl set-ntp on

# Add SSH key to all nodes
for node in "${storage[@]}"; do
  ssh-copy-id -i ~/.ssh/$certName $user@$node
done

# Ensure open-iscsi is installed locally (for mounting Longhorn volumes)
if ! systemctl is-active --quiet open-iscsi; then
  echo -e " \033[31;5mOpen-ISCSI not found or not running, installing...\033[0m"
  sudo apt update && sudo apt install -y open-iscsi
else
  echo -e " \033[32;5mOpen-ISCSI already installed and running\033[0m"
fi

# Read RKE2 token (must be in same dir as script)
if [[ ! -f token ]]; then
  echo -e " \033[31;1mERROR: token file not found in current directory\033[0m"
  exit 1
fi
token=$(cat token)

# Deploy RKE2 agents on each Longhorn node
for newnode in "${storage[@]}"; do
  echo -e " \033[34;1m>> Setting up RKE2 agent on $newnode...\033[0m"

  ssh -i ~/.ssh/$certName $user@$newnode <<EOF
    set -e
    sudo mkdir -p /etc/rancher/rke2
    sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOC
token: ${token}
server: https://${vip}:9345
node-label:
  - longhorn=true
EOC
    curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -
    sudo systemctl enable rke2-agent
    sudo systemctl start rke2-agent
EOF

  echo -e " \033[32;5m>> $newnode joined the cluster as a Longhorn node\033[0m"
done

# Step 2: Deploy Longhorn using a pinned manifest
echo -e " \033[34;1m>> Installing Longhorn...\033[0m"
kubectl apply -f https://raw.githubusercontent.com/JamesTurland/JimsGarage/main/Kubernetes/Longhorn/longhorn.yaml

# Wait for Longhorn pods to come up
echo -e " \033[34;1m>> Watching Longhorn pods...\033[0m"
kubectl get pods -n longhorn-system --watch &
WATCH_PID=$!

# Wait 20 seconds or until all pods are ready
sleep 20
kill $WATCH_PID &>/dev/null

# Confirm Longhorn setup
kubectl get nodes -o wide
kubectl get svc -n longhorn-system

echo -e " \033[32;1m>> Happy Kubing! Access Longhorn through Rancher UI or port-forward.\033[0m"
