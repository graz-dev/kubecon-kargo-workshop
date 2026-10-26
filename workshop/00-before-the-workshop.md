# 00 - Before the workshop

Do this a few days before, at home, on a good connection. It takes about 20 minutes, most of it downloading.

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

A new folder with files such as `Makefile` and `workshop.env`. You are now inside it.
</details>

## 2. Choose your prefix

Open `workshop.env` in an editor and set your prefix. Use your first name or a handle, in lowercase:

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

## Done

Keep the folder as it is, and see you at the workshop.

## Stuck?

Run `make bootstrap` again. If it still reports a problem you cannot fix, send the file `.tools/bootstrap-report.txt` to
**<SUPPORT_CONTACT>**. It has no passwords or tokens in it.
