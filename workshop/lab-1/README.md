# Lab 1 - Your first promotion

**Goal:** promote your first release to `dev`, and see who does what: Kargo changes Git, Argo CD changes the cluster. It takes about
15 minutes.

In this lab you work mainly with the **Kargo CLI**: every step is a command. The Kargo UI shows the same things, and the screenshots
tell you where to look. We will use the UI more in the next labs.

## 0. Get ready

In a new terminal, in this folder, put the tools on your path and log in to your Kargo. `make urls` prints the `kargo login` line with
your address and password filled in:

```sh
export PATH="$PWD/.tools/bin:$PATH"
make urls
kargo login <your Kargo address> --admin --password <your password>
kargo get projects
```

<details>
<summary>What it does</summary>

The first line lets your terminal find the `kargo` command we downloaded. `make urls` shows your address and password. `kargo login`
signs the command in to your Kargo, as `admin`; it is remembered, so you do it once. The last command lists your projects.
</details>

<details>
<summary>What you should see</summary>

The project `guestbook` is listed as ready:

```
NAME        READY   STATUS                                AGE
guestbook   True    Project is synced and ready for use   2m
```

Already did this at the end of guide 01? Then only the `export` line is needed in each new terminal.
</details>

## The words of this lab

- A **Warehouse** watches the places where new things appear, such as an image registry or a Git repository, and bundles what it finds.
- That bundle is **Freight**: one version of the image plus one commit of the chart, moving together.
- A **Stage** is a place Freight can be sent to, usually an environment such as `dev`.
- A **Promotion** is the act of sending Freight to a Stage. It is a list of steps that Kargo runs.

Know more: [Kargo core concepts](https://docs.kargo.io/user-guide/core-concepts/).

## 1. Create the Warehouse

Pretend the developers' pipeline has just shipped version 1.0.0 of the guestbook. Kargo has to be told where to look for it. Copy the
starting files to your work folder, and read the Warehouse:

```sh
mkdir -p work && cp -R workshop/lab-1 work/
cat work/lab-1/warehouse.yaml
```

There is nothing to change in it. Apply it:

```sh
kargo apply -f work/lab-1/warehouse.yaml
```

<details>
<summary>What it does</summary>

The file has two subscriptions. The first watches the guestbook image in the registry and picks the versions that match
`>=1.0.0 <=1.0.0`. The second watches the GitOps repository, only the `charts/` folder, because the chart travels with the image.
Everything the Warehouse finds is bundled into Freight.

About that odd constraint: in real life it would be `>=1.0.0`, and new versions would appear by themselves when developers push them.
Here every version already exists in the registry, so we put a fence at 1.0.0. In the next labs `make release VERSION=1.1.0` is the
button that moves the fence, as if the developers had shipped.

`kargo apply` sends the file to Kargo and creates or updates what is in it. You will use it for every file in these labs.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the Warehouse `app` was created.

In the Kargo UI, open the project `guestbook`. After a few seconds, a Warehouse called `app` appears in the pipeline view, with one piece of Freight next to it.

![](/assets/lab-1-first-warehouse.png)
</details>


## 2. Look at what was found

Run:

```sh
kargo get warehouses --project guestbook
kargo get freight --project guestbook
```

Wait up to a minute if the Freight list is empty.

<details>
<summary>What it does</summary>

The first command lists your Warehouses. The second lists the Freight they created. Each piece of Freight has a long name and a short
alias such as `wonky-wombat`. You will use the alias in a moment.
</details>

<details>
<summary>What you should see</summary>

One Warehouse `app`, and one piece of Freight with its alias. It contains the image at version 1.0.0 and one commit of the chart.

In the Kargo UI, click the Freight in the project view. A panel shows the image with its tag, and the Git commit. The alias is at the top.

![](/assets/lab-1-first-freight.png)

</details>
<br>

Know more: [Working with Warehouses](https://docs.kargo.io/user-guide/how-to-guides/working-with-warehouses) and
[Working with Freight](https://docs.kargo.io/user-guide/how-to-guides/working-with-freight).

## 3. Build the dev Stage

There is no `dev` Stage yet, so Freight has nowhere to go. You write it. Open `work/lab-1/stage-dev.yaml` and replace the three `TODO`s.
Read the five steps first: that list **is** the promotion.

<details>
<summary>What it does</summary>

A Stage says where it gets Freight from (`requestedFreight`) and what a promotion does (`promotionTemplate`). The steps here:

1. `git-clone` gets the GitOps repository.
2. `yaml-update` changes one value in the `dev` values file. This is where the new version goes.
3. `git-commit` records the change.
4. `git-push` sends it to Gitea.
5. `argocd-update` asks Argo CD to sync the `dev` application.

Notice that no step touches the cluster. Kargo only writes to Git.

The text between `${{` and `}}` is an expression. Kargo fills it in when the promotion runs.
</details>

<details>
<summary>Hint</summary>

- The image tag lives in the key `image.tag` of the values file.
- The tag of the image in the Freight is `imageFrom(vars.image).Tag`, written inside `${{ }}`.
- For the commit message, something like `Promote ${{ imageFrom(vars.image).Tag }} to ${{ ctx.stage }}` works.
</details>

Know more: [Working with Stages](https://docs.kargo.io/user-guide/how-to-guides/working-with-stages),
[Promotion steps](https://docs.kargo.io/user-guide/reference-docs/promotion-steps) and
[Expressions](https://docs.kargo.io/user-guide/reference-docs/expressions).

## 4. Apply the Stage

Run:

```sh
kargo apply -f work/lab-1/stage-dev.yaml
```

<details>
<summary>What it does</summary>

Sends the file to Kargo, which creates the Stage `dev` in your project.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the Stage, and `kargo get stages --project guestbook` now lists `dev`.

In the Kargo UI, the `dev` Stage appears in the project view, connected to the Warehouse. The UI can also create a Stage, either by
pasting YAML or by filling in a simple form.

![](/assets/lab-1-new-stage-pipeline-view.png)

![](/assets/lab-1-new-stage-details.png)
</details>

## 5. Promote the Freight and watch it work

Run, with the alias you saw in step 2:

```sh
kargo promote --project guestbook --freight-alias <alias> --stage dev
kargo get promotions --project guestbook --stage dev
```

Run the second command again until the Promotion has finished. It is fast.

<details>
<summary>What it does</summary>

The first command creates a Promotion: "send this Freight to `dev`". Kargo then runs the five steps of the Stage. The second command lists
the Promotions of `dev` and how each one is going.
</details>

<details>
<summary>What you should see</summary>

Kargo says the Promotion was created, with a name. A few seconds later the list shows it as **Succeeded**.

In the Kargo UI, the `dev` Stage now has the Freight promoted. Open the Promotion to see each step with how long it took, and open a
step to read its log.

![](/assets/lab-1-promotion-pipeline-freight-promoted.png)

![](/assets/lab-1-promotion-pipeline-promotion-details.png)

Now see the result with your own eyes:

- **Git:** open `http://gitea.localtest.me/workshop/guestbook-gitops/commits/branch/main`. There is a new commit by `kargo-bot`, and it
  changed the `dev` values file.

![](/assets/lab-1-git-change.png)

- **Argo CD:** the application `guestbook-dev` is synced to that commit.

![](/assets/lab-1-argo-ui.png)

- **The application:** open `http://guestbook-dev.localtest.me`. The banner is now blue and says **v1.0.0**. Open `http://guestbook-staging.localtest.me`: it still says v0.9.0.

![](/assets/lab-1-result.png)

</details>

<details>
<summary>What just happened</summary>

Kargo cloned the repository, changed one line, committed and pushed. Argo CD saw the new commit and updated the cluster. **Kargo wrote
to Git; Argo CD synced. Kargo never touched your cluster.**
</details>

## 6. Check your work

Run:

```sh
make check STEP=1
```

<details>
<summary>What it does</summary>

Checks that the Warehouse, the Freight, the `dev` Stage and the Promotion are in place, that Git and the `dev` application have the new
version, and that `staging` did not change. It also tells you if a `TODO` is left in your file.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does the whole lab for you, and you can read the finished files in `steps/1/`:

```sh
make catchup STEP=1
```

## Stuck?

- **The Promotion failed at the first step (`git-clone`):** the `repoURL` in your file is wrong. If your port is not 80, it must carry it.
- **`make check` says a `TODO` is left:** it tells you the line.
- **The Promotion failed at `git-push` with `could not read Username`:** Kargo has no permission to push. Run `make up` again and promote again.
- **Kargo says the Stage is invalid:** compare your file with the five steps above. Indentation matters in YAML.
