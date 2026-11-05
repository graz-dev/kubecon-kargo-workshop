# 00 - Before the workshop

**First, please fill in the [pre-workshop survey](https://docs.google.com/forms/d/e/1FAIpQLSfDFXU5C52IGLhklu1Ixu1GcCSi3oI8_T26wDZZh6LEnDxIWg/viewform).** It helps us prepare the workshop for you.

Then do this a few days before, at home, on a good connection. It takes about 40 minutes, most of it downloading and waiting.

You will also create your own Argo CD and Kargo on the Akuity Platform, and your cluster. Doing it now means that, on the day, a hundred
people do not wait for the platform at the same moment.

You need a Mac or a Linux laptop (on Windows, use WSL2) with:

- **Docker** running: Docker Desktop, Colima, Rancher Desktop or Docker Engine. Give it at least **8 GB of memory**.
- **git**, **make** and **curl**. On a Mac, `xcode-select --install` installs all three.
- About **15 GB of free disk**.
- A web browser, to sign in to the Akuity Platform. You create your account and your organization in step 3.

## 1. Get the workshop

Run:

```sh
git clone https://github.com/graz-dev/kubecon-kargo-workshop
cd kubecon-kargo-workshop
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

Your Argo CD and Kargo will be called `anna-workshop`, and your organization on the platform (next step) starts with the same word. The prefix
keeps your things apart from everyone else's.

Allowed: lowercase letters, digits and hyphens, starting with a letter, up to 12 characters.
</details>

<details>
<summary>What you should see</summary>

Nothing yet. Step 4 checks it.
</details>

## 3. Create your account and your organization

In your browser, open https://training.akuity.cloud/ and sign in. Then create **your own organization**. Its name is your `WORKSHOP_PREFIX`, then
`kubecon-workshop`, then four random digits that you make up:

```
anna-kubecon-workshop-4821
```

If the platform shows an error, for example because the name is already taken, change the four digits and try again.

<details>
<summary>What it does</summary>

https://training.akuity.cloud/ is the Akuity Platform we use in the workshop. The first time you sign in, it creates your account. Your Argo CD
and your Kargo will live in your own organization, and in nobody else's. The four digits make it unlikely that two people choose the same name.

You do this in the browser. `make login`, in step 6, signs in the command line later, with the same account.
</details>

<details>
<summary>What you should see</summary>

<!-- TODO(verify, add a screenshot): what the platform shows once the organization exists. -->
You are signed in, and your organization, with the name you chose, is the one you work in.
</details>

## 4. Prepare your laptop

Run:

```sh
make bootstrap
```

<details>
<summary>What it does</summary>

Downloads the small tools the workshop uses (`kind`, `kubectl`, `helm`, `kargo`, `akuity`, `crane`) into a folder inside the project.
Nothing is installed on your system. Then it checks Docker, memory, disk, your prefix and your connection to the services we use,
and writes a short report by itself, in `.tools/bootstrap-report.txt`, every time you run it. You only need the report if something is wrong:
then you send it to us (see Stuck? at the end). It has no passwords or tokens in it.
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
It is safe to run as many times as you like. If you cannot fix it, send us the report (see Stuck? at the end).
</details>

## 5. Download the images (recommended)

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

## 6. Sign in to the Akuity Platform from the command line

Run:

```sh
make login
```

<details>
<summary>What it does</summary>

Opens a sign-in with the Akuity CLI: it prints a link and a code. Open the link in your browser, enter the code and sign in with the same
account as in step 3. The session lasts about 12 hours.
</details>

<details>
<summary>What you should see</summary>

```
Authenticated as <your name> (<your e-mail>)
 ok  organization: anna-kubecon-workshop-4821
```
</details>

## 7. Create your cluster and your environment

Run:

```sh
make up
make seed
```

<details>
<summary>What it does</summary>

`make up` creates a Kubernetes cluster on your laptop, with a web entrance (Traefik) and local names such as `gitea.localtest.me`. Then it creates
your Argo CD and your Kargo on the Akuity Platform, and installs their agents in your cluster. The agents connect out to the platform, so
nothing on your laptop is opened to the network. It takes about 6 minutes the first time, and about a minute and a half if you run it again.

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

## 8. Check everything

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

You are ready when `make check STEP=setup` (step 8) says `All good.` Keep the folder as it is, and see you at the workshop. On the day,
[guide 01](01-your-environment.md) takes about ten minutes.

## Stuck?

- **Port 80 is in use:** set `HTTP_PORT=8080` in `workshop.env`, then run `make down` and `make up` again.
- **The platform says the name of your organization is taken:** change the four digits and try again. Then write the new name in `workshop.env`.
- **`make login` says your account has no organization named …, or belongs to several:** the name in `AKUITY_ORGANIZATION` in `workshop.env`
  must be exactly the name of the organization you created in step 3.
- **"You are not logged in":** run `make login` again. The session lasts about 12 hours.
- **A step stopped half way:** run the same command again. Every command is safe to repeat.
- **Still stuck:** run `make bootstrap` again. It writes the report `.tools/bootstrap-report.txt` by itself. If it still reports a problem
  you cannot fix, send that file to **marketing-team@akuity.io**. It has no passwords or tokens in it.
- **Anything else, or you cannot even get started:** write to **marketing-team@akuity.io** at any moment, at any step. You do not need a
  report. It can be that you cannot sign in, cannot clone the project, or `make bootstrap` does not start. Tell us the step number and what
  you see, and we will help you.
