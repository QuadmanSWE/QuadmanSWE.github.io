---
title: Quick guide to kuberenets on raspberry pi.
published: true
---

# Beyond Minikube - setting up two raspberry pi with k3s to get experience with kubernetes.

The scope of this post is not to give an introduction to what kubernetes is or why to use it.

Chances are if you find this post that you want to build a physical cluster on your home network and practice deploying services to it.

We will be using [k3s from rancher](https://k3s.io/) as our kubernetes distro.

- [Beyond Minikube - setting up two raspberry pi with k3s to get experience with kubernetes.](#beyond-minikube---setting-up-two-raspberry-pi-with-k3s-to-get-experience-with-kubernetes)
  - [Cluster infrastructure set up](#cluster-infrastructure-set-up)
    - [Unpacking and bootstrapping rasbian](#unpacking-and-bootstrapping-rasbian)
    - [Configuring raspbian after boot on each node](#configuring-raspbian-after-boot-on-each-node)
    - [Assiging static IP](#assiging-static-ip)
    - [Installing k3s on the first node](#installing-k3s-on-the-first-node)
    - [Installing and joining the other nodes](#installing-and-joining-the-other-nodes)
  - [The tools I use to interact with kubernetes from windows 10](#the-tools-i-use-to-interact-with-kubernetes-from-windows-10)
    - [kubectl and friends](#kubectl-and-friends)
    - [vs code extension](#vs-code-extension)
    - [kubernetes-dashboard](#kubernetes-dashboard)
  - [My first deployment](#my-first-deployment)
  - [Things you can do for fun and profit (extra credit and homework)](#things-you-can-do-for-fun-and-profit-extra-credit-and-homework)
    - [You own CA with your proper let's encrypt cert](#you-own-ca-with-your-proper-lets-encrypt-cert)
    - [Private container registry](#private-container-registry)
    - [](#)

## Cluster infrastructure set up

I bought the two rasberry pi, usb-c cables for power, some cute ebony and ivory cases and micro SD-cards from [https://www.inet.se/](Inet.se) (shout out to their webshop, expect more business from me).

![](../assets/k3s-shopping-list.png)

Once the package showed up, me and [Algaron87](https://twitter.com/Algaron87) unpacked everything and put the two raspberry pi into their cases. Algaron is my high school buddy / friend of the family / godfather of my children / all around good guy.

### Unpacking and bootstrapping rasbian

We unpacked the micro SD-cards and began flashing over a rasbian image that you can download here: https://downloads.raspberrypi.org/

The one we chose for the occation was ["2020-08-20-raspios-buster-arm64-lite.zip"](https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2020-08-24/2020-08-20-raspios-buster-arm64.zip).

We mounted the image and added an empty ssh file to the image before copying over to show that we wanted to use ssh in the future. We killed the ability to log on with password in the future in the sshd_config file.

I am using an old mp3 player ascesory as a docking station for micro SD-cards.

![](../assets/k3s-raspberry.jpg)

### Configuring raspbian after boot on each node

This is by far the most boring task if you have to redo it, because it involves physical labor.

[Reference this documetation on rasp-config.](https://www.raspberrypi.org/documentation/computers/configuration.html)

I named my nodes ds-pi-1 and ds-pi-2, assigning them ip addresses 192.168.0.78 and 192.168.0.79 respectively.

The one named ds-pi-2 became the master node. (We assigned this by which was the first case we unpacked and somehow switched SD-cards around and got them confused!)

``` bash
sudo raspi-config #follow the steps

mkdir /home/pi/.ssh

echo "<Mine and Algaron's ssh keys>" > /home/pi/.ssh/authorized_keys

sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/UsePAM yes.*/UsePAM no/' /etc/ssh/sshd_config

printf %s " cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" >> /boot/cmdline.txt

```

### Assiging static IP

You should set your static ip on the nodes and not in your router like I did to prevent issues with DNS inside the cluster. I don't care about that stuff and I live my life pretty much as a renegade, but please don't be like me.

![](../assets/k3s-router.png)

### Installing k3s on the first node

```bash
export K3S_KUBECONFIG_MODE=644
curl -sfL https://get.k3s.io | sh -
kubectl config view --raw #shows you the token you need to connect nodes and your dev environement
```

### Installing and joining the other nodes

Replace master ip and master key

``` bash
sudo curl -sfL https://get.k3s.io | K3S_URL="https://<master ip>:6443" K3S_TOKEN=<master key> sh -
```

## The tools I use to interact with kubernetes from windows 10

### kubectl and friends

``` powershell
choco install kubernetes-cli --y
choco install kubernetes-helm --y
choco install kubernetes-kompose --y
```

![](../assets/k3s-choco-list.png)

You can connect to the cluster by showing the info from the cluster 

Save the output from the config in the cluster to a config file and put it into a file named config under ~/.kube. Merge it if you have a file from before for one or more other clusters.

![](../assets/k3s-config.png)

Now we can check out our deployment status 

```
kubectl get nodes
``` 
![](../assets/k3s-get-nodes.png)

### vs code extension

### kubernetes-dashboard

Three lines of code that are run on the master node from https://rancher.com/docs/k3s/latest/en/installation/kube-dashboard/

After exporting the bearer token I put it into my keepass database and I copy paste it from there whenever I use the dashboard.

I built this cute powershell wrapper function to connect to any application, with a specific implementation in a different function for the dashboard app itself. These get loaded as part of my powershell profile

``` powershell
Function Connect-KubeApplication {
	param(
		[int]$localport,
		[int]$clusterport,
		[string]$servicename,
		[string]$namespace = $servicename,
		[string]$path = '',
		[Parameter(Mandatory=$false)][ValidateSet('http','https')][string]$protocol = 'https'
	)
	start-process chrome "$($protocol)://localhost:$localport/$path"
	kubectl port-forward -n $namespace service/$servicename "$localport`:$clusterport" --address 0.0.0.0
}
Function Connect-KubeDashBoard {
	param([int]$localport = 10443)
	Connect-KubeApplication -localport $localport -clusterport 443 -servicename 'kubernetes-dashboard'
}
```

Now I can connect like so to the dashboard: 
```powershell
Connect-KubeDashBoard
```

My shell will spit out the port forward command that was run and the reponse.

![](../assets/k3s-Connect-KubeDashBoard.png)

It will also surf to the application with chrome.

![](../assets/k3s-surf-dashboard.png)

## My first deployment

helm qr thing

![](../assets/k3s-get-pods.png)

## Things you can do for fun and profit (extra credit and homework)

### You own CA with your proper let's encrypt cert



### Private container registry

Rather than putting the docker images I build myself on docker hub I would like to host them directly inside the cluster, that way there isn't a roundtrip up to the Internet all the time.

### 