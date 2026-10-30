# 01 - Your environment

You do this at the start of the workshop. It takes about 10 minutes.

You created your cluster, your Git server and your own Argo CD and Kargo before the workshop, in [guide 00](00-before-the-workshop.md).
Today you check that they are still fine, and you look around. **Did not do guide 00?** Do it now, all of it: it takes about 40 minutes. Then come back here.

Open a terminal in the workshop folder.

## 1. Sign in again

Run:

```sh
make login
```

<details>
<summary>What it does</summary>

Your session on the Akuity Platform lasts about 12 hours, so the one from a few days ago has ended. This prints a link and a code: open the link in
your browser, enter the code and sign in. If you are still signed in, it only shows who you are.
</details>

<details>
<summary>What you should see</summary>

```
Authenticated as <your name> (<your e-mail>)
 ok  organization: <the organization>
```
</details>

## 2. Check that everything is still there

Run:

```sh
make check STEP=setup
```

<details>
<summary>What it does</summary>

Checks your cluster, Gitea, your Argo CD and Kargo, the connection between them, the Kargo project and the five applications. It changes nothing.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says:

```
All good.
```

A line starting with `FAIL` has an arrow under it saying what to do. If your laptop was restarted, or Docker was updated since guide 00, something
may need repair: run `make up`, then `make seed`, and check again. Both are safe to repeat and are quick when nothing is missing.
</details>

## 3. Open Argo CD and Kargo

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

You get in. Argo CD has five applications and Kargo has one project. The next step looks at them.
</details>

## 4. Look around

Take a few minutes to see what you have.

- **Argo CD:** five applications, `guestbook-dev` to `guestbook-prod-emea`, **Synced** and **Healthy**.
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

## 5. Log in to the Kargo CLI

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

## Done

Your environment is ready. Leave the terminal open: the labs start from here.

## Stuck?

- **"You are not logged in":** run `make login` again.
- **A step stopped half way:** run the same command again. Every command is safe to repeat.
- **Still stuck:** run `make doctor` and show the output to a helper.
