# add-vmct-to-pve-ha-resources

This repository contains a helper script that adds all virtual machines (VMs)
and containers (CTs) in a Proxmox VE cluster to a predefined HA group. VMs that
use passthrough PCI devices are skipped so they remain bound to the node where
the device is available.

## Usage

Run `add-vmct-to-pve-ha-resources.sh` on a cluster node with sufficient privileges.
The script will create the HA group if it does not already exist and add every
eligible VM and CT to it.
