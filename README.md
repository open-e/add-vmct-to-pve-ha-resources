# add-vmct-to-pve-ha-resources
Adds all virtual machines (VMs) and containers (CTs) in a Proxmox cluster to an HA group

This repository contains a helper script that adds all virtual machines (VMs)
and containers (CTs) in a Proxmox VE cluster to a predefined HA group. VMs that
use passthrough PCI devices are skipped so they remain bound to the node where
the device is available.

## Usage

Run the following commands on a Proxmox VE host to download and execute the helper script:

```bash
wget https://raw.githubusercontent.com/open-e/add-vmct-to-pve-ha-resources/main/add-vmct-to-pve-ha-resources.sh \
    -O /usr/local/sbin/add-vmct-to-pve-ha-resources; \
chmod +x /usr/local/sbin/add-vmct-to-pve-ha-resources; \
add-vmct-to-pve-ha-resources
```

When executed, the script will create the HA group if it does not already exist
and then add every eligible VM and CT to it. VMs using passthrough devices are
skipped automatically.
