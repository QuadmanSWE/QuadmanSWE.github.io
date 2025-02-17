---
title: Utilizing nvidia hardware in kubernetes built ontop of virtual machines
published: true
excerpt_separator: <!--more-->
---

With the advent of large language models, I thought it might be fun to try and get one to run locally and figure out what it would take to run it as a service.

<!--more-->

## The plan

After having gotten an LLM to run locally on Windows 11 and then querying it with open webui, I would like to replicate the setup on kubernetes.

I started reading and came up with a rough idea of the steps involved and what I needed to do to execute them.

1. Get the GPU to run in a VM
   a. Configure the hypervisor to be able to passthrough the GPU
   b. Create an Ubuntu VM and install nvidia drivers
   c. Install docker in the VM and run nvidka-smi to verify
2. Clone an additional talos VM for my cluster and attach the GPU to it.
   a. Prepare the talos image of the gpu node to include the required drivers
   b. Update my management repo of talos to cater to an third type of node (control, worker, gpu)
   c. Set up node labels, tains, and any other configurations pertaining to gpu nodes
3. Make the GPU available in kubernetes
   a. Install nvidia device plugin
   b. Create runtime class
   c. Test out tolerations against gpu taints
4. Schedule ollama on the gpu node and configure open webui as a front end.

## The end results

Look at that, all in a couple of weeks hard trial and error.

What I dubbed my SQL Genie is now explaining columnstore indexes in SQL Server to me.

![](../assets/2025-02-17-15-34-51-chatting-with-sqlgenie.png)

## Step by step

### Ollama locally

First thing is first, how do we run ollama locally?

Make sure you have working drivers for your graphics card, then install ollama from their site.
Set up the model you want to serve. You could get this to run as a service on windows with nssm.
I chose to interact with it with open webui because it is available on docker hub and that translates nicely into the kubernetes setup.

### PCIe passthrough on proxmox

Proxmox is the hypervisor that I dual boot into besides Windows 11 on my system.

There are a bunch of different guides and troubleshooting guides which I used. [At the center stood the wiki entry from the proxmox community](https://pve.proxmox.com/wiki/PCI_Passthrough).

In essence the goal is to make sure that the gpu hardware can be mounted and utilized as if it was native to the virtualized operating system.

This comes with a bunch of challanges such as making sure the host operating system (proxmox) doesn't use the graphics card in any way itself.

Let's skip over all of the painstaking device configuration and near death experience trying to restore functionality to Windows 11 again after tinkering with iommu and blacklisting devices and disconnecting cables.

After getting everything restored and then configured in the right order I can verify that the device is availble and in its own iommu group.

``` bash

cat /proc/cmdline; for d in /sys/kernel/iommu_groups/*/devices/*; do n=${d#*/iommu_groups/*}; n=${n%%/*}; printf 'IOMMU groups %s ' "$n"; lspci -nns "${d##*/}"; done

```

As we can see the nvidia device is in iommu group 12, and has deviceid 01:00

{% highlight text mark_lines="12 13" %}
IOMMU groups 0 00:01.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14da]
IOMMU groups 10 00:14.0 SMBus [0c05]: Advanced Micro Devices, Inc. [AMD] FCH SMBus Controller [1022:790b] (rev 71)
IOMMU groups 10 00:14.3 ISA bridge [0601]: Advanced Micro Devices, Inc. [AMD] FCH LPC Bridge [1022:790e] (rev 51)
IOMMU groups 11 00:18.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e0]
IOMMU groups 11 00:18.1 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e1]
IOMMU groups 11 00:18.2 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e2]
IOMMU groups 11 00:18.3 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e3]
IOMMU groups 11 00:18.4 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e4]
IOMMU groups 11 00:18.5 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e5]
IOMMU groups 11 00:18.6 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e6]
IOMMU groups 11 00:18.7 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14e7]
IOMMU groups 12 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD103 [GeForce RTX 4080] [10de:2704] (rev a1)
IOMMU groups 12 01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:22bb] (rev a1)
IOMMU groups 13 02:00.0 Non-Volatile memory controller [0108]: Micron/Crucial Technology T700 NVMe PCIe SSD [c0a9:5419]
IOMMU groups 14 03:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Upstream Port [1022:43f4] (rev 01)
IOMMU groups 15 04:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 16 04:08.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 17 04:09.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 18 04:0a.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 18 08:00.0 Ethernet controller [0200]: Intel Corporation Ethernet Controller I225-V [8086:15f3] (rev 03)
IOMMU groups 19 04:0b.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 19 09:00.0 Network controller [0280]: MEDIATEK Corp. MT7921K (RZ608) Wi-Fi 6E 80MHz [14c3:0608]
IOMMU groups 1 00:01.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Device [1022:14db]
IOMMU groups 20 04:0c.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 20 0a:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset USB 3.2 Controller [1022:43f7] (rev 01)
IOMMU groups 21 04:0d.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
IOMMU groups 21 0b:00.0 SATA controller [0106]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset SATA Controller [1022:43f6] (rev 01)
IOMMU groups 22 0c:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Raphael [1002:164e] (rev c9)
IOMMU groups 23 0c:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt Radeon High Definition Audio Controller [1002:1640]
IOMMU groups 24 0c:00.2 Encryption controller [1080]: Advanced Micro Devices, Inc. [AMD] VanGogh PSP/CCP [1022:1649]
IOMMU groups 25 0c:00.3 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Device [1022:15b6]
IOMMU groups 26 0c:00.4 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Device [1022:15b7]
IOMMU groups 27 0d:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Device [1022:15b8]
IOMMU groups 2 00:01.2 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Device [1022:14db]
IOMMU groups 3 00:02.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14da]
IOMMU groups 4 00:02.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Device [1022:14db]
IOMMU groups 5 00:03.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14da]
IOMMU groups 6 00:04.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14da]
IOMMU groups 7 00:08.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:14da]
IOMMU groups 8 00:08.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Device [1022:14dd]
IOMMU groups 9 00:08.3 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Device [1022:14dd]
{% endhighlight %}

### Trying it out with Ubuntu

I created a new VM from scratch with a ubuntu live server image.

On the hardware page I can now safely attach the pci device for my graphics card (though it can of course only be used by one running VM at a time).

After the installations I rebooted and installed docker and the appropriate drivers following the examples from nvidia together with their container toolkit. [Full guide on their site](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

With that I could run a container on the VM which could use the gpu passed through from proxmox.

![](../assets/2025-02-07-17-16-12-nvidia-smi-in-ubuntu-docker.png)

### Getting everything set up for talos

Talos is the linux distro on top of which I choose to run kubernetes.

[Here is the talos image I configured for the gpu node](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline-set=true&extensions=-&extensions=siderolabs%2Fbtrfs&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Fnvidia-container-toolkit-production&extensions=siderolabs%2Fnvidia-open-gpu-kernel-modules-production&extensions=siderolabs%2Fqemu-guest-agent&platform=metal&secureboot=undefined&target=metal&version=1.9.3)

I added extensions according to the [guide on the talos site](https://www.talos.dev/v1.9/talos-guides/configuration/nvidia-gpu-proprietary/).