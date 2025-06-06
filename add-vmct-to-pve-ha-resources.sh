#!/bin/bash

set -euo pipefail

# ---- Configuration ---------------------------------------------------------
GROUP="powernodes"
GROUP_NODES=("pve1" "pve2")  # Define as array for future flexibility
# ---------------------------------------------------------------------------

# Optional: enable persistent logging
# exec > >(tee -a /var/log/add-ha-resources.log) 2>&1

# ---- Function: log ---------------------------------------------------------
log() {
  echo "[$(date +%H:%M:%S)] $*"
}
# ---------------------------------------------------------------------------

# ---- Function: get_groups --------------------------------------------------
get_groups() {
  ha-manager groupconfig 2>/dev/null | grep -E '^group:' | awk '{print $2}'
}
# ---------------------------------------------------------------------------

# ---- Function: get_vms_with_hostpci ----------------------------------------
get_vms_with_hostpci() {
  grep -Rl hostpci /etc/pve/nodes/*/qemu-server/*.conf 2>/dev/null | \
    sed -nE 's#.*/([0-9]+)\.conf#\1#p' | sort -u
}
# ---------------------------------------------------------------------------

# ---- Function: get_cluster_resources ---------------------------------------
get_cluster_resources() {
  pvesh get /cluster/resources --type vm --output-format=json
}
# ---------------------------------------------------------------------------

# 1) Ensure jq is installed
command -v jq >/dev/null 2>&1 || {
  log "jq not found, installing..."
  apt update && apt install -y jq
  clear
}

# 2) Ensure HA group exists
NODES_CSV=$(IFS=, ; echo "${GROUP_NODES[*]}")
if ! get_groups | grep -qw "$GROUP"; then
  log "Group '$GROUP' does not exist. Creating restricted group on nodes: $NODES_CSV"
  ha-manager groupadd "$GROUP" \
    --nodes "$NODES_CSV" \
    --restricted 1 \
    --comment "Auto-created by add-vmct-to-pve-ha-resources.sh"
fi

# 3) Collect VMIDs using PCI passthrough
readarray -t HOSTPCI_VMS < <(get_vms_with_hostpci)

log "This script will add all VMs and CTs to the HA group '$GROUP'"
log "VMs using PCI passthrough (hostpci) will be skipped."
log "Target HA nodes: $NODES_CSV"
read -n 1 -s -r -p "Press any key to continue or Ctrl-C to exit..." _
echo

# 4) Process and add resources
get_cluster_resources | jq -r '
  .[]
  | select(.type=="qemu" or .type=="lxc")
  | (if .type=="qemu" then "vm:" else "ct:" end) + (.vmid | tostring)
' | while read -r sid; do
  TYPE=${sid%%:*}
  VMID=${sid#*:}

  # Skip hostpci VMs
  if [[ "$TYPE" == "vm" ]] && [[ " ${HOSTPCI_VMS[*]} " == *" $VMID "* ]]; then
    log "Skipping vm:$VMID (hostpci present)"
    continue
  fi

  # Skip if already in HA group
  if ha-manager status | awk '{print $1}' | grep -qx "$sid"; then
    continue
  fi

  log "Adding $sid to HA group \"$GROUP\""
  ha-manager add "$sid" --state started --group "$GROUP" \
    --comment "HA ${VMID} on ${NODES_CSV}"
done
