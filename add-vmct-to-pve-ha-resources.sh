#!/bin/bash

# set -euo pipefail

# ---- Configuration ---------------------------------------------------------
GROUP="ha-nodes"
# ---------------------------------------------------------------------------

# ---- Function: log ---------------------------------------------------------
log() {
  echo "[$(date +%H:%M:%S)] $*"
}
# ---------------------------------------------------------------------------

# ---- Function: get_groups -------------------------------------------------
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

# ---- Discover and sort all PVE nodes --------------------------------------
ALL_NODES=( $(pvesh get /nodes --output-format=json \
    | python3 -c '
import sys, json
nodes = json.load(sys.stdin)
# extract and sort the "node" values, then join with spaces
print(" ".join(sorted(n["node"] for n in nodes)))
'
))
# ---------------------------------------------------------------------------

# ---- Prompt user to select HA nodes ----------------------------------------
echo "Available PVE nodes:"
for idx in "${!ALL_NODES[@]}"; do
  printf "  %2d) %s\n" $((idx+1)) "${ALL_NODES[$idx]}"
done

while true; do
  read -rp "Enter two node numbers (e.g. 1 2) to include in HA group \"$GROUP\": " n1 n2
  # validate input
  if [[ -z "${n1:-}" || -z "${n2:-}" ]]; then
    echo "Please enter two numbers."
    continue
  fi
  # check bounds
  max=${#ALL_NODES[@]}
  if (( n1 < 1 || n1 > max || n2 < 1 || n2 > max )); then
    echo "Selections must be between 1 and $max."
    continue
  fi
  # prevent duplicates
  if [[ "$n1" -eq "$n2" ]]; then
    echo "Please choose two different nodes."
    continue
  fi
  break
done

GROUP_NODES=("${ALL_NODES[$((n1-1))]}" "${ALL_NODES[$((n2-1))]}")
NODES_CSV=$(IFS=, ; echo "${GROUP_NODES[*]}")

log "Selected HA nodes: $NODES_CSV"
# ---------------------------------------------------------------------------

# ---- 1) Ensure HA group exists --------------------------------------------
if ! get_groups | grep -qw "$GROUP"; then
  log "Group '$GROUP' does not exist. Creating restricted group on nodes: $NODES_CSV"
  ha-manager groupadd "$GROUP" \
    --nodes "$NODES_CSV" \
    --restricted 1 \
    --comment "Auto-created by add-vmct-to-pve-ha-resources.sh"
fi
# ---------------------------------------------------------------------------

# ---- 2) Collect VMIDs using PCI passthrough --------------------------------
readarray -t HOSTPCI_VMS < <(get_vms_with_hostpci)

log "This script will add all VMs and CTs to the HA group '$GROUP'"
log "VMs using PCI passthrough (hostpci) will be skipped."
log "Target HA nodes: $NODES_CSV"
read -n 1 -s -r -p "Press any key to continue or Ctrl-C to exit..." _
echo
# ---------------------------------------------------------------------------

# ---- 3) Process and add resources -----------------------------------------
pvesh get /cluster/resources --type vm --output-format=json | \
python3 -c "
import sys, json
mapping = {'qemu': 'vm', 'lxc': 'ct'}
print('\n'.join(
    f\"{mapping[o['type']]}:{o['vmid']}\" 
    for o in json.load(sys.stdin)
    if o['type'] in mapping
))
" | while read -r sid; do
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
