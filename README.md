# Talos Bootstrap for bare metal clusters

Prerequisites:
- TalosCTL installed
- Docker Installed and Host networking is available
- Etcher or DD to burn the custom iPXE boot image. (Optional)
- Small flash drive or CD
- iPXE supported NIC.
- Kubectl Installed
- WSL if on Windows using Ubuntu

Recommended:
- Load balancer to split load across control plane nodes.

Warnings:
- Ensure your TalosCTL version matches the exact version of the Talos you are going to be deploying. This is critical as you will run into many weird issues if you don't follow this.
- Double check the IP settings on the matchbox control plane profile for the initial control plane node. Messing this up can cause your initial control plane node to be unreachable. Kernel args are not persisted on reboots.
- If you have freezing issues with Talos on startup and are using an AMD GPU you likely need to install the AMD driver patches. The patched images for this can be generated [here](https://factory.talos.dev/) The patches I needed for my specific AMD setup were: `siderolabs/amdgpu-firmware (20240513)` and `siderolabs/amd-ucode (20240513)`. This one in particular caused a lot of headaches.
- Since I don't feel like altering my DHCP server I opted to use iPXE with matchbox using a custom init script. 
- With my 2.5Gbe Realtek NICs they don't work for installation because iPXE lacks the needed drivers. You may need to bootstrap using the onboard NIC and switchover in the machine config.  
- If using IPV6 and IPV4 I highly recommend forcing the default IPV4 gateway in the machine config as I experienced an issue where Talos grabbed onto the IPV6 gateway address.

## Talos config setup

1. First thing we need to do is generate config files for our Talos Cluster. These patches contain the bare minimum to get the cluster up and running. Additional configuration may be required based on your setup for additional information on config options look [here](https://www.talos.dev/v1.7/reference/configuration/v1alpha1/config/). The following strategic merge patches are included:

```yaml
# all.yaml
machine:
  install:
    disk: /dev/nvme0n1
    # Picking the right NVME disk can be a bit annoying this might take a few attempts.
    image: ghcr.io/siderolabs/installer:v1.7.0
    wipe: true
    extraKernelArgs:
      - talos.platform=metal
      - reboot=k
---
# cp.yaml
machine:
  network: 
    interfaces:
# Since the system only has one interface we force it to hold onto a static IP for the initial node.
    - deviceSelector:
        physical: true
      dhcp: false
# The initial control plane node should have a static IP address outside of the DHCP range. On my second node I have incremented the IP by one address.
      addresses:
        - 10.10.1.201/16
# If you can host a separate load balancer I recommend doing that instead of the VIP as it complicates network setup.
      vip:
        ip: 10.10.2.150
# I needed to force this for the control plane nodes as they kept latching onto the IPV6 gateway.
      routes:
        - network: 0.0.0.0/0 # The route's network (destination).
          gateway: 10.10.1.1 # The route's gateway (if empty, creates link scope route).
# Since this cluster is small I want to leverage all available compute.
cluster:
  allowSchedulingOnControlPlanes: true
```

Let's generate the configurations for our cluster. The initial IP used to generate the configuration should match your load balancer or be mapped to the first control plane nodes IP. The latter is not recommended for production usage but makes homelab setup simpler.
```bash
cd talos-machineconfigs &&
talosctl gen config test-cluster https://<FIRST_NODE_IP>:6443 --config-patch @all.yaml --config-patch-control-plane @cp.yaml 
# Use this flag if you want to patch the workers as well --config-patch-worker @work.yaml
```

## matchbox setup

2. First thing we want to do is identify the MAC address of our first control plane node. I recommend the control plane nodes have static IP addresses and workers use DHCP with static leases. Here are the example `groups` for a 2 node control plane and N number of workers. The workers are the default configuration. The workers use DHCP to configure themselves. :
`groups/control-plane-node1.json`
```json
{
    "id": "control-plane-node1",
    "name": "control-plane-node1",
    "profile": "control-plane-node1",
    "selector": {
        "mac": "<net0 MAC address of node1>"
    }
}
```
`groups/control-plane-node2.json`
```json
{
    "id": "control-plane-node2",
    "name": "control-plane-node2",
    "profile": "control-plane-node2",
    "selector": {
        "mac": "<net0 MAC address of node2>"
    }
}
```
`groups/default`
```json
{
    "id": "default",
    "name": "default",
    "profile": "default"
}
```

These `groups` determine which `profiles` are applied to the nodes connecting to our matchbox server. For my setup I have the following profiles. Based on which nodes connect to matchbox a different profile is applied. The only difference between the control plane `profiles` is the address set on the physical interface in the Talos machineconfig. The `profile` for default is applied to every device connecting that does not meet the requirements of the `group` selectors specified above:

`profiles/control-plane-node1.json`
```json
{
    "id": "control-plane-node1",
    "name": "control-plane-node1",
    "boot": {
        "kernel": "/assets/vmlinuz",
        "initrd": [
            "/assets/initramfs.xz"
        ],
        "args": [
            "initrd=initramfs.xz",
            "init_on_alloc=1",
            "init_on_free=1",
            "slab_nomerge",
            "pti=on",
            "console=tty0",
            "console=ttyS0",
            "printk.devkmsg=on",
            "ip=<FIRST_NODE_IP>::10.10.1.1:255.255.0.0::eno1:off:::",
            "talos.platform=metal",
            "talos.config=http://<MATCHBOX_SERVER_IP>:8080/assets/controlplane1.yaml"
        ]
    }
}
```
`profiles/control-plane-node2.json`
```json
{
    "id": "control-plane-node2",
    "name": "control-plane-node2",
    "boot": {
        "kernel": "/assets/vmlinuz",
        "initrd": [
            "/assets/initramfs.xz"
        ],
        "args": [
            "initrd=initramfs.xz",
            "init_on_alloc=1",
            "init_on_free=1",
            "slab_nomerge",
            "pti=on",
            "console=tty0",
            "console=ttyS0",
            "printk.devkmsg=on",
            "ip=<SECOND_NODE_IP>::10.10.1.1:255.255.0.0::eno1:off:::",
            "talos.platform=metal",
            "talos.config=http://<MATCHBOX_SERVER_IP>:8080/assets/controlplane2.yaml"
        ]
    }
}
```
`profiles/default.json`
```json
{
    "id": "default",
    "name": "default",
    "boot": {
        "kernel": "/assets/vmlinuz",
        "initrd": [
            "/assets/initramfs.xz"
        ],
        "args": [
            "initrd=initramfs.xz",
            "init_on_alloc=1",
            "init_on_free=1",
            "slab_nomerge",
            "pti=on",
            "console=tty0",
            "console=ttyS0",
            "printk.devkmsg=on",
            "talos.platform=metal",
            "talos.config=http://<MATCHBOX_SERVER_IP>:8080/assets/worker.yaml"
        ]
    }
}
```

## iPXE loader setup

2. This step is entirely optional but you can build your own custom iPXE boot drive [docs](https://ipxe.org/embed). For our purposes we embed a small script that will point to the host IP of our matchbox server. In this case it's my desktop running Docker desktop with host networking enabled on port 8080. Alternatively you could just install the bare iPXE loader and type in the following commands listed in the script below. 

```ipxe
#!ipxe
echo Configure dhcp .... &&
dhcp &&
chain http://<MATCHBOX_SERVER_IP>:8080/boot.ipxe
```

```bash
# Install dependencies for building iPXE
sudo apt install mkisofs genisoimage isolinux syslinux mtools liblzma-dev -y
git clone 
git clone https://github.com/ipxe/ipxe.git
cd ipxe/src
make 
# Embed boot script from above.
make bin/ipxe.lkrn bin-x86_64-efi/ipxe.efi EMBED=boot.ipxe
 ./util/genfsimg -o ipxe.usb bin/ipxe.lkrn bin-x86_64-efi/ipxe.efi
```

You are now ready to use Etcher or DD to write the ipxe.usb file to a flash drive.

## Talos cluster creation

3. Let's begin the process of creating our cluster. First thing we need to is copy the `assets,profiles and groups` to the matchbox directory. The images specified below have the AMD patches applied to them to fix my freezing issue. You can use the image factory to generate images with the patches you need for your hardware. [Image factory](https://factory.talos.dev/)

```bash
# Copying configurations for matchbox to use.
sudo mkdir -p /var/lib/matchbox/assets &&
sudo cp talos-machineconfigs/*.yaml /var/lib/matchbox/assets &&
sudo mkdir -p /var/lib/matchbox/profiles &&
sudo cp profiles/* /var/lib/matchbox/profiles &&
sudo mkdir -p /var/lib/matchbox/groups &&
sudo cp groups/* /var/lib/matchbox/groups &&
# Grabbing kernel images so matchbox can use them. These were generated with the AMD patches described above.
sudo wget -O /var/lib/matchbox/assets/vmlinuz https://pxe.factory.talos.dev/image/f19ad7b4a5d29151f3a59ef2d9c581cf89e77142e52f0abb5022e8f0b95ad0b9/v1.7.6/kernel-amd64 &&
sudo wget -O /var/lib/matchbox/assets/initramfs.xz https://factory.talos.dev/image/f19ad7b4a5d29151f3a59ef2d9c581cf89e77142e52f0abb5022e8f0b95ad0b9/v1.7.6/initramfs-amd64.xz &&
# Starting matchbox with the mounts we created beforehand.
sudo docker run -d --net=host --rm -v /var/lib/matchbox:/var/lib/matchbox:Z -v /etc/matchbox:/etc/matchbox:Z,ro quay.io/poseidon/matchbox:v0.10.0 -address=0.0.0.0:8080 -log-level=debug
```

On your cluster machines set the primary boot device to be your iPXE flash drive. The system will grab a DHCP address to start talking with the matchbox server. Based on the contents of the get request from the machine matchbox will serve up the profile it matches with. This can take a while so be patient.

## Control plane bootstrapping

4. The initial control plane will come online and begin in an unhealthy state as `etcd` is not bootstrapped. To fix this we need to run the following commands:

```bash
cd talo-machineconfigs
# etcd bootstrap
talosctl --talosconfig talosconfig config endpoint <FIRST_NODE_IP>
talosctl --talosconfig talosconfig config node <FIRST_NODE_IP>
talosctl --talosconfig talosconfig bootstrap
talosctl --talosconfig talosconfig kubeconfig .
# You should be able to see the nodes at this point
kubectl --kubeconfig kubeconfig get nodes
# Updating machine config if you have a typo
talosctl --talosconfig talosconfig -n <FIRST_NODE_IP> -e <FIRST_NODE_IP> apply machineconfig -f controlplane1.yaml --mode=no-reboot
```
