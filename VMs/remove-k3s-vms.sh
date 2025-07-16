#!/usr/bin/env bash
# remove-k3s-vms.sh
# This script will force-stop (if running) and destroy the specified Proxmox VMs without waiting for a graceful shutdown.

set -euo pipefail

# List of VM IDs to remove
VM_IDS=(311 312 313 321 322)

for VMID in "${VM_IDS[@]}"; do
  echo "\nProcessing VM ID: $VMID"

  # Force-stop the VM if it is running
  if qm status "$VMID" | grep -qw running; then
    echo " - Stopping VM $VMID (force)..."
    qm stop "$VMID"
    echo "   VM $VMID stopped."
  else
    echo " - VM $VMID is not running."
  fi

  # Destroy the VM and purge all associated data
  echo " - Destroying VM $VMID..."
  qm destroy "$VMID" --purge
  echo "   VM $VMID destroyed."
done

echo "\nAll specified VMs have been removed."
