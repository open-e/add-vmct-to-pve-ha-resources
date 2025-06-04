#!/bin/bash

set -euo pipefail

# ---- Configuration ---------------------------------------------------------
# Change GROUP if you want a different HA group name.
GROUP="powernodes"
# Adjust these node names if your "power" nodes differ.
GROUP_NODES="pve1,pve2"
# ---------------------------------------------------------------------------

# ---- Function: get_groups --------------------------------------------------
# Retrieve all existing HA group names by parsing the output of 'ha-manager groupconfig'.
# It looks for lines beginning with "group:" and extracts the second word.
get_groups() {
  ha-manager groupconfig 2>/dev/null | grep -E '^group:' | awk '{print $2}'
}
# ---------------------------------------------------------------------------

# ---- Function: get_vms_with_hostpci -----------------------------------------
# Scan each VM configuration under /etc/pve/nodes/*/qemu-server for the
# "hostpci" option. VMs that define this directive rely on PCI passthrough and
# should remain on the node that provides the hardware. The function extracts
# the VMID from every matching configuration file and outputs a unique,
# sorted list of those IDs.
get_vms_with_hostpci() {
  grep -Rl hostpci /etc/pve/nodes/*/qemu-server/*.conf 2>/dev/null | \
    sed -E 's#.*/([0-9]+)\.conf#\1#' | sort -u
}
# ---------------------------------------------------------------------------

# 1) Install jq if missing
command -v jq >/dev/null 2>&1 || {
  echo "jq not found, installing..."
  apt update && apt install -y jq
}

# 2) Ensure HA group exists (or create it as a restricted group on GROUP_NODES)
if ! get_groups | grep -qw "$GROUP"; then
  echo "Group '$GROUP' does not exist. Creating restricted group on nodes: $GROUP_NODES"
  ha-manager groupadd "$GROUP" \
    --nodes "$GROUP_NODES" \
    --restricted 1 \
    --comment "Auto-created by add-vmct-to-pve-ha-resources.sh"
fi

# 3) Build an array of VMIDs that have hostpci devices
readarray -t HOSTPCI_VMS < <(get_vms_with_hostpci)

echo "This script will add all VMs and CTs to the HA group '$GROUP'"
echo "on nodes: $GROUP_NODES. VMs using PCI passthrough will be skipped."
read -n 1 -s -r -p "Press any key to continue or Ctrl-C to exit" _
echo

# 4) Loop over every VM/CT in the cluster and add to HA if not using hostpci
pvesh get /cluster/resources --type vm --output-format=json | \
  jq -r '
    .[]
    | select(.type=="qemu" or .type=="lxc")
    | (if .type=="qemu" then "vm:" else "ct:" end) + (.vmid | tostring)
  ' | while read -r sid; do
      # Parse type ("vm" or "ct") and numeric ID
      TYPE=${sid%%:*}
      VMID=${sid#*:}

      # If this is a VM, skip it if its ID appears in HOSTPCI_VMS
      if [ "$TYPE" = "vm" ]; then
        for skip_id in "${HOSTPCI_VMS[@]}"; do
          if [ "$VMID" = "$skip_id" ]; then
            echo "Skipping vm:$VMID (hostpci present)"
            continue 2
          fi
        done
      fi

      # Skip if already in HA
      if ha-manager status | grep -qE "^$sid\b"; then
        continue
      fi

      echo "Adding $sid -> HA group \"$GROUP\""
      ha-manager add "$sid" --state started --group "$GROUP" \
        --comment "HA ${VMID} on $GROUP_NODES"
  done
