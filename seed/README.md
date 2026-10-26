# guestbook-gitops

The GitOps repository of the Kargo workshop.

- `charts/guestbook` is the Helm chart of the guestbook.
- `env/<stage>/k8s/values.yaml` is the only thing that differs per environment. A Kargo promotion changes
  `image.tag` in one of these files and Argo CD deploys it.

This repository is created and reset by `make seed` / `make reset` of the workshop repository.
