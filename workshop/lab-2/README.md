# Lab 2 - Build the pipeline

**Goal:** turn `dev` into a pipeline. You add `staging` after `dev`, let `dev` promote new releases by itself, and keep `staging` as a gate
that waits for you. It takes about 15 minutes.

You still work with the **Kargo CLI**. This time the Kargo UI is worth a look too: it draws your pipeline.

Before you start, finish Lab 1. `make check STEP=1` should say `All good.` If it does not, run `make catchup STEP=1`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- A **pipeline** is a row of Stages. Freight goes through them in order: a Stage only takes Freight that has already been in the Stage
  before it.
- **Auto-promotion** means Kargo creates the Promotion by itself when new Freight is available for a Stage. A Stage without it is a **gate**:
  it waits for a person.
- The **ProjectConfig** holds the settings of a project. Here it says which Stages promote by themselves.

Know more: [Working with Stages](https://docs.kargo.io/user-guide/how-to-guides/working-with-stages) and
[Working with Projects](https://docs.kargo.io/user-guide/how-to-guides/working-with-projects).

## 1. Add the staging Stage

Copy the starting files to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-2 work/
```

Open `work/lab-2/stage-staging.yaml` and replace the three `TODO`s. Compare it with your `dev` Stage: it is almost the same.

<details>
<summary>What it does</summary>

Two things change from `dev`:

- **Where the Freight comes from.** `dev` takes Freight straight from the Warehouse. `staging` takes it from `dev`. This one line is what
  makes a pipeline.
- **What it changes.** `staging` writes to its own values file, and tells Argo CD to sync its own application.

The five promotion steps are the same as in `dev`.
</details>

<details>
<summary>Hint</summary>

- The Stage before `staging` is `dev`.
- The values file of `dev` is `./repo/env/dev/k8s/values.yaml`. The one of `staging` follows the same pattern.
- The Argo CD application of `dev` is `guestbook-dev`.
</details>

Apply it:

```sh
kargo apply -f work/lab-2/stage-staging.yaml
```

<details>
<summary>What you should see</summary>

Kargo confirms the Stage, and `kargo get stages --project guestbook` now lists `dev` and `staging`.

In the Kargo UI, open the project `guestbook`. The pipeline now reads Warehouse, `dev`, `staging`, left to right.

![](/assets/lab-2-new-stage.png)

</details>

## 2. Let dev promote by itself

Open `work/lab-2/project-config.yaml` and replace the two `TODO`s. Then apply it:

```sh
kargo apply -f work/lab-2/project-config.yaml
```

<details>
<summary>What it does</summary>

A promotion policy picks Stages by name and says whether Kargo promotes new Freight to them. You turn it on for `dev`.

`staging` is not in the list, so it stays manual: the default is that nobody promotes unless you do.
</details>

<details>
<summary>Hint</summary>

- The Stage that promotes by itself is `dev`.
- `autoPromotionEnabled` is a boolean: `true` or `false`.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the ProjectConfig. Nothing else happens yet: `dev` already has the newest Freight, so there is nothing new to promote.

You can see that your changes were effective from the UI because now the `dev` stage has a thunder icon: 

![](/assets/lab-2-auto-promotion.png)

</details>

## 3. A new release arrives

Pretend the developers have just shipped version 1.1.0. Run:

```sh
make release VERSION=1.1.0
kargo get freight --project guestbook
kargo get promotions --project guestbook --stage dev
```

Run the last two commands again until you see a new Freight and a new Promotion. It takes up to a minute.

<details>
<summary>What it does</summary>

`make release` moves the fence of your Warehouse from 1.0.0 to 1.1.0, as if the developers had pushed a new image. Kargo finds it and
creates a new piece of Freight.

Because auto-promotion is on, Kargo promotes that Freight to `dev` by itself. **You did not run `kargo promote`.**
</details>

<details>
<summary>What you should see</summary>

Two pieces of Freight now, and two Promotions on `dev`. The newer Promotion was created by Kargo and goes to **Succeeded**.

![](/assets/lab-2-new-freight-and-new-promotion.png)

Open `http://guestbook-dev.localtest.me`: the banner says **v1.1.0**. 

![](/assets/lab-2-dev-autopromotion.png)

Open `http://guestbook-staging.localtest.me`: it still says v0.9.0.

![](/assets/lab-2-staging-not-yet-promoted.png)

Nobody moved `dev` but Kargo, and no CI job was involved.

</details>

## 4. Promote to staging

`staging` is a gate: it waits for you. First make sure the new Promotion on `dev` shows **Succeeded**, then run:

```sh
kargo promote --project guestbook --stage staging --warehouse app
kargo get promotions --project guestbook --stage staging
```

Run the second command again until the Promotion has finished.

<details>
<summary>What it does</summary>

The first command creates a Promotion to `staging`. With `--warehouse`, Kargo picks the newest Freight that `staging` can take, which is
the one that went through `dev`: 1.1.0. It is the same choice auto-promotion would make. The difference is that **you** made the decision.

You can also choose a piece of Freight yourself, with `--freight-alias <alias>` as in Lab 1.
</details>

<details>
<summary>What you should see</summary>

![](/assets/lab-2-full-pipeline.png)

The Promotion goes to **Succeeded**. Open `http://guestbook-staging.localtest.me`: the banner now says **v1.1.0**.

![](/assets/lab-2-stagin-promoted.png)

In the Kargo UI, you can also promote by hand: choose the Freight, then **Promote**, then `staging`.

</details>

<details>
<summary>What just happened</summary>

`dev` is automatic, `staging` is a gate. Same Freight, same steps. The only difference is one policy in the ProjectConfig.
</details>

## 5. Check your work

Run:

```sh
make check STEP=2
```

<details>
<summary>What it does</summary>

Checks that `staging` exists, that auto-promotion is on, that `dev` had a second Promotion without you, that `dev` and `staging` run 1.1.0
in Git and in the cluster, and that production did not change. It also tells you if a `TODO` is left in your files.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 and 2 for you, and you can read the finished files in `steps/2/`:

```sh
make catchup STEP=2
```

## Stuck?

- **`dev` did not move after `make release`:** give it a minute. Then look at `kargo get projectconfig --project guestbook -o yaml`: it must
  say `autoPromotionEnabled: true` for `dev`.
- **The promote to `staging` finds nothing to promote:** `dev` has not finished yet. Wait for its Promotion to succeed, then try again.
- **`staging` shows v1.0.0, not v1.1.0:** you promoted a few seconds too early, when only the old Freight could go to `staging`. Run
  `kargo get freight --project guestbook`, take the alias of the newest Freight (the one with the smallest age), and promote it:
  `kargo promote --project guestbook --freight-alias <alias> --stage staging`.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses the file:** compare it with the example above. Indentation matters in YAML.

## One more thing

Look at `dev` and `staging` side by side: their five steps are almost identical. Kargo can share steps between Stages with **Promotion
Tasks**, so you write them once. We do not use them in this workshop, but it is good to know:
[Promotion Tasks](https://docs.kargo.io/user-guide/reference-docs/promotion-tasks).
