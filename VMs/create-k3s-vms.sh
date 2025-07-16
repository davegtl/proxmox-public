#!/usr/bin/env bash
# create-k3s-vms.sh
# Clones a Proxmox VM template (ID 5000) into control-plane and worker nodes,
# with colored headers, green ASCII progress bars, resource settings, and auto-boot,
# suppressing cloud-init Perl warnings on start.

set -euo pipefail

### Configuration ###
TEMPLATE_ID=5000            # ID of the template VM to clone
CLONE_STORAGE="tank"       # Storage target for cloned disks
CLONE_MODE="full"          # Clone mode: "full" or "linked"

# Control-plane nodes
CP_TARGETS=(
  "311:k3s-cp01"
  "312:k3s-cp02"
  "313:k3s-cp03"
)
CP_CORES=2                   # CPU cores for control-plane nodes
CP_MEM=4096                  # RAM in MiB for control-plane nodes

# Worker nodes
WORKER_TARGETS=(
  "321:k3s-w01"
  "322:k3s-w02"
)
WORKER_CORES=2               # CPU cores for worker nodes
WORKER_MEM=12288             # RAM in MiB for worker nodes
###########################

# ANSI color sequences
RED=$'\e[31m'
YELLOW=$'\e[33m'
GREEN=$'\e[32m'
NC=$'\e[0m'

# Display a green ASCII progress bar
# $1 = percentage (integer)
display_progress() {
  local pct=${1:-0}
  local width=50
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar
  bar=$(printf "%0.s#" $(seq 1 $filled))
  bar+=$(printf "%0.s-" $(seq 1 $empty))
  printf "\r%b[%s] %3d%%%b" "$GREEN" "$bar" "$pct" "$NC"
}

# Clone a VM and show progress
# $1 = VMID, $2 = NAME
clone_vm() {
  local vmid="$1"
  local name="$2"
  echo
  echo "Creating VM ${name}..."

  qm clone "$TEMPLATE_ID" "$vmid" \
    --name "$name" \
    --storage "$CLONE_STORAGE" \
    --$CLONE_MODE 2>&1 | \
  while IFS= read -r line; do
    if [[ "$line" =~ ^create[[:space:]]full ]]; then
      continue
    elif [[ $line =~ transferred.*\ \(([0-9]+(\.[0-9]+)?)%\) ]]; then
      pct_float="${BASH_REMATCH[1]}"
      pct_int=${pct_float%.*}
      display_progress "$pct_int"
    fi
  done
  echo
}

# Configure and boot VM (suppress cloud-init Perl warnings)
# $1 = VMID, $2 = NAME, $3 = CORES, $4 = MEMORY
configure_and_boot() {
  local vmid="$1"
  local name="$2"
  local cores="$3"
  local mem="$4"

  echo "Setting resources for VM ${vmid}: cores=${cores}, memory=${mem}MiB"
  qm set "$vmid" --cores "$cores" --memory "$mem"
  echo "Booting VM ${name}..."
  # Suppress uninitialized value warnings from Cloudinit.pm
  qm start "$vmid" 2>&1 | grep -v "Use of uninitialized value in split"
}

# Process a group of VMs
# $1 = array name, $2 = cores, $3 = mem, $4 = header, $5 = color
process_group() {
  local -n targets=$1
  local cores=$2
  local mem=$3
  local header=$4
  local color=$5

  printf "%b== %s ==%b\n" "$color" "$header" "$NC"

  for entry in "${targets[@]}"; do
    IFS=":" read -r vmid name <<< "$entry"
    clone_vm "$vmid" "$name"
    configure_and_boot "$vmid" "$name" "$cores" "$mem"
  done
}

# Main execution
process_group CP_TARGETS "$CP_CORES" "$CP_MEM" "Creating Control-Plane VMs" "$RED"
process_group WORKER_TARGETS "$WORKER_CORES" "$WORKER_MEM" "Creating Worker VMs" "$YELLOW"

# Done
echo
