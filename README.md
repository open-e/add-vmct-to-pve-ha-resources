
You can verify the group was created with:

```bash
ha-manager groupconfig
```

Example output when only the `powernodes` group exists:

```
group: powernodes
        comment Auto-created by add-vmct-to-pve-ha-resources.sh
        nodes pve2,pve1
        restricted 1
```
