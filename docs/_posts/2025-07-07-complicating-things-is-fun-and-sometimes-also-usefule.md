---
title: Complicating things is fun and sometimes also useful
published: true
excerpt_separator: <!--more-->
tags: keycloak authz cdk8s argocd backstage crossplane
---

All I wanted was to make an elegant way for requesting an external hostname in my api gateway as part of my ingress abstraction.

<!--more-->

![TODO INSERT PICTURE FROM LINUX LAPTOP HERE OF MY ABOMIATION]()

Once I actually got this to work I took a step back and wondered how did I get here?

![rant from bluesky](../assets/2025-07-07_21-27-55-blueskypost.png)

[Picture is from this post](https://bsky.app/profile/dsoderlund.consulting/post/3lqv3nf7esc2i)

## The problem I want to solve

I want to be able to create a new file with one or more URLs. All the files in the folder will together be an array of valid redirect URLs for my oauth2proxy client in keycloak such that external traffic for new apps on those hostnames will be valid for authorization without allowing everything and anything. I want this configuration to be in git to allow gitops work, add new configuration with templates without changing files, and to be able to remove or change a file to update the configuration in keycloak.

Strap yourselves in, this is a journey!

## Background

So I have worked a lot with templates in backstage as part of my work with the platform. In my interest in being able to let applications and their dependant resources have a shared lifecyle, I have often chosen to use crossplane over terraform so that it all fits together nicely when prototyping and demonstrating ideas.

### Home lab setup

In my homelab I have this setup.

![](../assets/2025-07-07_20-24-30-homelab-setup.png)

Basically traffic can reach my cluster in a couple of different ways. I have two different ingress gateways, one bound to hostnames which resolvable and routable externally with public DNS, and one bound to *.mgmt.dsoderlund.consulting which is resolvable and routable locally or with VPN.

For the public addresses some are via a cloudflare vpn tunnel, and some are "old school not so secure" port-forwarded via the static public IP from my ISP. Usually this is turned off except when holding an interactive demonstration with others.

### Lifecycle of a fullstack app

In a recent webinar I wanted to demonstrate this lifecycle bundling in a template, such that you would input information about your new app and you would get a new repo, a new deployment, and a registration in the catalog which would then link to everything providing a single pane of glass.

![](../assets/2025-07-07_20-30-27-twelvefactorapp.png)

So when using my "fullstackapp" template what happens is of course that the four different resources get created (frontend, backend, ingress, database).

### Gitops

What I expect is that I can then make changes or remove those resources from the gitops-repo and the desired state of my infrastructure will be reconciled accordingly.

Lastly I want the structure of my gitops-repo to be add only if possible, that is **I don't want to write code for my templates that make changes to existing files** because then I have leaky abstractions.

The public repo I am using for the new fullstack app demonstration is here: https://github.com/dsoderlund-consulting/demo-gitops

### My backstage template

The template format looks like this.

![TODO PICTURE OF BACKSTAGE TEMPLATE GOES HERE]()


Things to highlight:
- The hostname will be `<componentname>.example.com` and an ingress will be created if we tick the ingress box.
- The database connection details will be injected as environment variables if we tick the database box.
- Frontend bundle and backend server will both run on the same hostname but backend will use /api prefix.

And the resulting link from backstage to argocd would look like this. Very nice.

[Check out the full webinar here](https://www.youtube.com/watch?v=0-5HOpMCTiw)

## Hostname in backstage template to valid callback URL

Ok, so we know from our form that the user can request which hostname to use.

Given our initial requirement of a bunch of files with one or more URLs, why not just create a new file for each component in a folder and have those be put together as the configuration for keycloak?

### Enter crossplane

The first issue of course is how do we configure keycloak with gitops? Should we call terraform? [No we are using crossplane here and this excellent provider for keycloak.](https://github.com/crossplane-contrib/provider-keycloak)

Next problem, how do we create a nice abstraction of an oidc-client which doesn't require changes to any files?

### Content from any number of files should populate array of a kubernetes resource

My first idea was to use kustomize and splice things together with patches, but it turns out that kustomize doesn't support globbing or any way I could figure out to go from multiple files whose names are not known without changing the kustomization files into one field in a resource.

Again, the point here is that the backstage template will create a new file with the hostname we want, it shouldn't have to change any existing files or know any other structure.

One could conceivably construct a helm chart but at that point you are making things complicated without the fun part which is what this post is all about!

It then dawned on me that I already have the ~~perfect~~ solution from [my post about cdk8s in argocd](./2024-06-06-cdks8s-through-argocd).

### cdk8s

With cdk8s we can render the resource defintion (yaml or json) that we want argocd to deploy, or in my case I can check it in as is and let my argocd plugin figure it out (less recommended, more fun).

Here is my general idea of something to put into gitops to create the oauth2proxy client configuration I want.

1. Import the crossplane keycloak CRD to the new cdk8s folder
2. Write some typescript to read the files in the folder and create an array of strings.
3. Validate each URL with regex
4. Construct the openid client resource.

Again the code is publically available on github if you want to check it out further.


``` sh
kubectl get crds openidclient.keycloak.crossplane.io -o json | cdk8s import /dev/stdin
```

``` typescript
import { Construct } from "constructs";
import { App, Chart, ChartProps } from "cdk8s";
import {
  Client,
  ClientSpecDeletionPolicy,
  ClientSpecManagementPolicies,
} from "./imports/openidclient.keycloak.crossplane.io";
import * as path from "path";
import { getValidRedirectUrisFromDnsNames } from "./getValidRedirectUrisFromDnsNames";

export class MyChart extends Chart {
  constructor(
    scope: Construct,
    id: string,
    props: ChartProps = { disableResourceNameHashes: true }
  ) {
    super(scope, id, props);
    const allowedDnsNamesFolder = path.join(__dirname, "allowedDnsNames");
    const dynamicallyGeneratedRedirectUris = getValidRedirectUrisFromDnsNames(
      allowedDnsNamesFolder
    );
    new Client(this, "client", {
      metadata: {
        name: "oauth2proxy",
        annotations: {
          "dsoderlund.consulting/rendered-by": "cdk8s",
          "dsoderlund.consulting/managed-by": "crossplane",
        },
      },
      spec: {
        providerConfigRef: {
          name: "keycloak-config",
        },
        deletionPolicy: ClientSpecDeletionPolicy.ORPHAN,
        managementPolicies: [ClientSpecManagementPolicies.VALUE_ASTERISK],
        forProvider: {
          import: true,
          accessType: "CONFIDENTIAL",
          clientId: "oauth2proxy",
          description:
            "Generated through cdk8s and applied with crossplane (you can't make changes to this in the keycloak UI, they will be overwritten)",
          realmId: "master",
          validRedirectUris:
            dynamicallyGeneratedRedirectUris.length > 0
              ? dynamicallyGeneratedRedirectUris
              : undefined,
        },
      },
    });
  }
}

const app = new App();
new MyChart(app, "oauth2proxy-shared-config");
app.synth();
```

## Wrap up

Great, so now I can have my backstage template clone the gitops repo, add the file with the hostname I my application should have, once synched we can surf to that address and be served a working application. Once I grow tired of this app we just remove the file together with the rest of the application configuration and the valid callback urls for the client in keycloak get fewer.