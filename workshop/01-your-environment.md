# 01 - Your environment

You do this at the start of the workshop. It takes about 10 minutes, and most of it is waiting.

At the end you will have your own Kubernetes cluster on your laptop, a Git server inside it, and your own Argo CD and Kargo on the
Akuity Platform, with five small applications already running.

Open a terminal in the workshop folder.

## 1. Sign in to the Akuity Platform

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

## 2. Check your laptop

Run:

```sh
make doctor
```

<details>
<summary>What it does</summary>

Reads the state of your laptop and your connection. It changes nothing.
</details>

<details>
<summary>What you should see</summary>

The last line is `Ready`. A warning is fine. A line marked `FAIL` is not: it says what to fix.
</details>

## 3. Create your cluster

Run:

```sh
make up
```

<details>
<summary>What it does</summary>

Creates a Kubernetes cluster on your laptop, with a web entrance (Traefik) and local names such as `gitea.localtest.me`. Then it creates your
Argo CD and your Kargo on the Akuity Platform, and installs their agents in your cluster. The agents connect out to the platform, so
nothing on your laptop is opened to the network.

It takes about 6 minutes the first time, and about 40 seconds if you run it again.
</details>

<details>
<summary>What you should see</summary>

It ends with your two addresses and your login:

```
The cluster is connected to the Akuity Platform.
  Argo CD: https://<id>.cd.akuity.cloud
  Kargo:   https://<id>.kargo.akuity.cloud
  Log in with:  admin  /  <your password>
```
</details>

## 4. Open Argo CD and Kargo

Run:

```sh
make urls
```

Open the Argo CD and Kargo addresses in your browser and sign in as `admin` with the password shown.

<details>
<summary>What it does</summary>

Prints your addresses and your login. The password is created for you and stays on your laptop, in `.tools/admin.env`.
</details>

<details>
<summary>What you should see</summary>

You get in. Argo CD has no applications yet, and Kargo has no projects yet. The next step fills them.
</details>

## 5. Create the starting point

Run:

```sh
make seed
```

<details>
<summary>What it does</summary>

Installs Gitea, a small Git server, inside your cluster, and puts in it the repository the workshop works on. It then creates five
applications in Argo CD, one for each environment (`dev`, `staging` and three production regions), and a project called `guestbook`
in Kargo. All five applications start on version `0.9.0`, the version that runs before Kargo.

It takes about a minute.
</details>

<details>
<summary>What you should see</summary>

At the end:

```
Seeded. Argo CD will create the five Applications; they run version 0.9.0.
```
</details>

## 6. Look around

Take a few minutes to see what you now have.

- **Argo CD:** five applications, `guestbook-dev` to `guestbook-prod-emea`. They become **Synced** and **Healthy** within a minute or two.
- **Kargo:** a project called `guestbook`. It is empty: you build the pipeline in the labs.
- **Gitea:** open `http://gitea.localtest.me` and sign in as `attendee` with the password `attendee-pw`. Open the repository
  `workshop/guestbook-gitops`.
- **The application:** open `http://guestbook-dev.localtest.me`.

<details>
<summary>What you should see</summary>

The application page has a grey banner that says **v0.9.0 - What runs today, before Kargo**. The other four environments show the same
page: `guestbook-staging`, `guestbook-prod-amer-east`, `guestbook-prod-amer-west` and `guestbook-prod-emea`, all at
`.localtest.me`. In the labs, you will watch the banner change colour and number as releases move through.

If you use another port than 80, add it to the address, for example `http://gitea.localtest.me:8080`.
</details>

## 7. Log in to the Kargo CLI

The labs use the `kargo` command. Put your tools on your path, then log in. `make urls` prints both lines for you, with your address and
password filled in:

```sh
export PATH="$PWD/.tools/bin:$PATH"
kargo login <your Kargo address> --admin --password <your password>
kargo get projects
```

<details>
<summary>What it does</summary>

The first line lets your terminal find the tools we downloaded for you, in this terminal window only. The second signs the `kargo`
command in to your Kargo, as the `admin` account. The third lists the projects you can see.
</details>

<details>
<summary>What you should see</summary>

The last command shows the project `guestbook` as ready:

```
NAME        READY   STATUS                                AGE
guestbook   True    Project is synced and ready for use   2m
```

Open a new terminal window later? Run the `export PATH=...` line again. The login is remembered.
</details>

## 8. Check everything

Run:

```sh
make check STEP=setup
```

<details>
<summary>What it does</summary>

Checks all of the above in one go: your cluster, Gitea, your Argo CD and Kargo, the connection between them, the Kargo project and the
five applications. It changes nothing.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says:

```
All good.
```

A line starting with `FAIL` has an arrow under it saying what to do.
</details>

## Done

Your environment is ready. Leave the terminal open: the labs start from here.

## Stuck?

- **Port 80 is in use:** set `HTTP_PORT=8080` in `workshop.env`, then run `make down` and `make up` again.
- **"You are not logged in":** run `make login` again. The session lasts about 12 hours.
- **A step stopped half way:** run the same command again. Every command is safe to repeat.
- **Still stuck:** run `make doctor` and show the output to a helper.
