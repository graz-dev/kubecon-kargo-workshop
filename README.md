# GitOps Workshop with Kargo and Argo CD

Hands-on labs for **KubeCon + CloudNativeCon North America 2026**, Salt Lake City.

You build a promotion pipeline for a small web application, `guestbook`. A new image version appears, and **Kargo** moves it through
`dev`, `staging` and three production regions by committing to Git. **Argo CD** syncs the cluster from Git. You see who does what, and
how to add checks, rollbacks and approvals along the way.

## What you run

- **On your laptop:** a [kind](https://kind.sigs.k8s.io/) cluster with Gitea (the Git server), the guestbook applications and the
  agents. Everything is created by the scripts in this repository.
- **On the [Akuity Platform](https://akuity.io/):** one hosted Argo CD and one hosted Kargo, both created for you by `make up`.

## What you need

Docker, `git`, `make`, `bash`, `curl`, internet access, and an Akuity Platform account. The other tools (kind, kubectl, helm, kargo,
akuity) are downloaded into `.tools/` for you. Nothing is installed on your system.

At least 8 GB of memory for Docker, and 15 GB of free disk space.

## Start here

1. Read [the guides](workshop/README.md). Start with [Before the workshop](workshop/00-before-the-workshop.md): it asks you to
   prepare your laptop and create your environment a few days before the event.
2. On the day, follow [Your environment](workshop/01-your-environment.md): it takes about ten minutes. Then do the labs in order.

`make help` lists every command.

## Layout

| Folder | What is in it |
|---|---|
| `workshop/` | The guides and, in `lab-N/`, the files you fill in |
| `steps/` | The finished files of each lab, used by `make check` and `make catchup` |
| `platform/`, `kind/`, `manifests/`, `seed/` | What `make up` and `make seed` create |
| `scripts/` | The scripts behind every `make` command |

The guestbook images are built from a separate repository and published as public packages on GitHub Container Registry.
