# 00 - Before the workshop

Do this a few days before, at home, on a good connection. It takes about 40 minutes, most of it downloading and waiting.

You will also create your own Argo CD and Kargo on the Akuity Platform, and your cluster. Doing it now means that, on the day, a hundred
people do not wait for the platform at the same moment.

You need a Mac or a Linux laptop (on Windows, use WSL2) with:

- **Docker** running: Docker Desktop, Colima, Rancher Desktop or Docker Engine. Give it at least **8 GB of memory**.
- **git**, **make** and **curl**. On a Mac, `xcode-select --install` installs all three.
- About **15 GB of free disk**.
- An **Akuity Platform account**. <!-- TODO(organizers): say how attendees get access (invitation e-mail, card, ...). -->

## 1. Get the workshop

Run:

```sh
git clone <WORKSHOP_REPO_URL>
cd <WORKSHOP_REPO_FOLDER>
```

<details>
<summary>What it does</summary>

Copies the workshop to your laptop. Everything you run during the workshop is in this folder.
</details>

<details>
<summary>What you should see</summary>

A new folder with files such as `Makefile` and `workshop.env.example`. You are now inside it.
</details>

## 2. Choose your prefix

Make your own copy of the settings, open it in an editor, and set your prefix. Use your first name or a handle, in lowercase:

```sh
cp workshop.env.example workshop.env
```

In `workshop.env`:

```sh
WORKSHOP_PREFIX=anna
```

<details>
<summary>What it does</summary>

Your Argo CD and Kargo will be called `anna-workshop`. Many people may share one Akuity organization, and the prefix keeps your
things apart from everyone else's.

Allowed: lowercase letters, digits and hyphens, starting with a letter, up to 12 characters.
</details>

<details>
<summary>What you should see</summary>

Nothing yet. The next step checks it.
</details>

## 3. Prepare your laptop

Run:

```sh
make bootstrap
```

<details>
<summary>What it does</summary>

Downloads the small tools the workshop uses (`kind`, `kubectl`, `helm`, `kargo`, `akuity`, `crane`) into a folder inside the project.
Nothing is installed on your system. Then it checks Docker, memory, disk, your prefix and your connection to the services we use,
and writes a short report you can send us.
</details>

<details>
<summary>What you should see</summary>

At the end:

```
All set. Nothing else to do until the workshop. Keep this folder as it is.
```

The tools are now in the folder `.tools/bin`, not on your system. In the labs you type `kargo` yourself, so every time you open a
new terminal in this folder, first run:

```sh
export PATH="$PWD/.tools/bin:$PATH"
```

If something is wrong, it lists what, for example `Docker memory`, `port 80` or `WORKSHOP_PREFIX`. Fix it and run the command again.
It is safe to run as many times as you like.
</details>

## 4. Download the images (recommended)

Run:

```sh
make prefetch
```

<details>
<summary>What it does</summary>

Downloads the container images the workshop needs, about 4 GB on disk. Doing it now means you do not depend on the venue Wi-Fi.
</details>

<details>
<summary>What you should see</summary>

A line for each image it downloads, and at the end the same number twice:

```
<n> of <n> images are on this machine (0 could not be pulled)
```
</details>

## 5. Sign in to the Akuity Platform

Run:

```sh
make login
```

<details>
<summary>What it does</summary>

Opens a sign-in with the Akuity CLI: it prints a link and a code. Open the link in your browser, enter the code and sign in.
The session lasts about 12 hours.
</details>

<details>
<summary>What you should see</summary>

```
Authenticated as <your name> (<your e-mail>)
 ok  organization: <the organization>
```
</details>

## 6. Create your cluster and your environment

Run:

```sh
make up
make seed
```

<details>
<summary>What it does</summary>

`make up` creates a Kubernetes cluster on your laptop, with a web entrance (Traefik) and local names such as `gitea.localtest.me`. Then it creates
your Argo CD and your Kargo on the Akuity Platform, and installs their agents in your cluster. The agents connect out to the platform, so
nothing on your laptop is opened to the network. It takes about 6 minutes the first time, and about 40 seconds if you run it again.

`make seed` installs Gitea, a small Git server, inside your cluster, and puts in it the repository the workshop works on. It then creates five
applications in Argo CD, one for each environment (`dev`, `staging` and three production regions), and a project called `guestbook`
in Kargo. All five applications start on version `0.9.0`, the version that runs before Kargo. It takes about a minute.
</details>

<details>
<summary>What you should see</summary>

`make up` ends with your two addresses and your login:

```
The cluster is connected to the Akuity Platform.
  Argo CD: https://<id>.cd.akuity.cloud
  Kargo:   https://<id>.kargo.akuity.cloud
  Log in with:  admin  /  <your password>
```

`make seed` ends with:

```
Seeded. Argo CD will create the five Applications; they run version 0.9.0.
```
</details>

## 7. Check everything

Run:

```sh
make check STEP=setup
```

<details>
<summary>What it does</summary>

Checks all of the above in one go: your cluster, Gitea, your Argo CD and Kargo, the connection between them, the Kargo project and the five
applications. It changes nothing.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says:

```
All good.
```

A line starting with `FAIL` has an arrow under it saying what to do. Right after `make seed`, the applications may need a minute or two to become
**Synced** and **Healthy**: if only those lines fail, wait a little and run the check again.

You will open Argo CD, Kargo and the application on the day of the workshop.
</details>

## Done

Your environment is ready. Keep the folder as it is, and see you at the workshop. On the day, [guide 01](01-your-environment.md) takes
about ten minutes.

## Stuck?

- **Port 80 is in use:** set `HTTP_PORT=8080` in `workshop.env`, then run `make down` and `make up` again.
- **"You are not logged in":** run `make login` again. The session lasts about 12 hours.
- **A step stopped half way:** run the same command again. Every command is safe to repeat.
- **Still stuck:** run `make bootstrap` again. If it still reports a problem you cannot fix, send the file `.tools/bootstrap-report.txt` to
  **the address that `make bootstrap` prints** (it is `SUPPORT_CONTACT` in `workshop.env`). It has no passwords or tokens in it.
