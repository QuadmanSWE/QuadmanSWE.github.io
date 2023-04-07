---
title: The Joy of Kubernetes 2 - Let us Encrypt
published: true
---

# Welcome to the Joy of Kubernetes

If you are new to the series, check out [the previous post](../he-joy-of-kubernetes-1-argocd-with-private-git-repo) about Argo CD if you like, we will leverage Argo CD a bit to deploy what we are doing today. You can just as well replace Argo CD with applying the manifests or helm charts manually.

In this second entry in The Joy of Kubernetes we will take a closer look at the Cert-Manager and it's ClusterIssuer resource. I am interested in requesting and issuing TLS certificates as secrets in kubernetes by just asking nicely, particulary for a real external DNS.

- [Welcome to the Joy of Kubernetes](#welcome-to-the-joy-of-kubernetes)
  - [Prerequisites 🎨](#prerequisites-)
  - [Overview](#overview)

## Prerequisites 🎨

- ~~A canvas, some brushes, and some paint~~  A kubernetes cluster and kubectl.
- Optinal, Argo CD with the application set creation from [the previous post](../he-joy-of-kubernetes-1-argocd-with-private-git-repo).
- A domain that you control
- A [supported DNS provider](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers)

## Overview

So glad you could join us for this post about Cert-Manager, ACME, and Let's Encrypt.

The basic concept is that by interacting with the API of one of the [supported DNS provider](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers), we can get some resource in our cluster to react to the fact that TLS certificates appear to be being required, and issue them by posing an ACME challenge to Let's Encrypt.

That resource is [Cert-Manager](https://cert-manager.io/docs/).

Here is what the flow looks like.



There are a lot of different ways to give the Cert-Manager ceritificate requests beyond the native resource defintion. There are also a lot of things for which you might want to request certificates beyond proving the authenticity of your service to incoming requests and encrypting with TLS.

Read up on the cert-manager documentation for what else you can use it for that fits your needs.


