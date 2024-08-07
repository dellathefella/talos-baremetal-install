```bash
talosctl --talosconfig talosconfig -n 10.10.1.200 -e 10.10.1.200 apply machineconfig -f controlplane.yaml --mode=no-reboot
talosctl --talosconfig talosconfig -n 10.10.1.200 -e 10.10.1.200 dashboard
talosctl --talosconfig talosconfig -n 10.10.1.72 -e 10.10.1.200 reset --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --reboot
```