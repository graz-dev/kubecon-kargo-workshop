# Lab 3 - Production in three regions

**Goal:** build production. One gate called `prod`, and three regions that follow it by themselves. One decision, three deployments. It
takes about 10 minutes.

You still work with the **Kargo CLI**, and the Kargo UI shows the result.

Before you start, finish Lab 2. `make check STEP=2` should say `All good.` If it does not, run `make catchup STEP=2`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- A **fan-out** is one Stage that feeds several Stages after it. Here `prod` feeds three regions.
- **Following** a Stage (`MatchUpstream`) means a Stage takes exactly the Freight that the Stage before it has now, and not the newest one.
- A **pattern** in a policy picks several Stages with one line, for example every name that starts with `prod-`.

Know more: [Working with Stages](https://docs.kargo.io/user-guide/how-to-guides/working-with-stages) and
[Patterns](https://docs.kargo.io/user-guide/patterns).

## 1. Add the prod Stage

Copy the starting files to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-3 work/
```

Open `work/lab-3/stage-prod.yaml` and replace the two `TODO`s. Then apply it:

```sh
kargo apply -f work/lab-3/stage-prod.yaml
```

<details>
<summary>What it does</summary>

`prod` is the gate before production, like `staging` was before it. It takes Freight from `staging`.

Look at its steps: it changes the values file of **all three regions**, makes one commit, and pushes. There is no `argocd-update` step,
because `prod` is not an application. It only writes to Git. The regions do the rest.
</details>

<details>
<summary>Hint</summary>

- The Stage before `prod` is `staging`.
- The third region is `prod-emea`. Its values file follows the pattern of the other two.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the Stage, and `kargo get stages --project guestbook` lists `prod`.

In the Kargo UI, `prod` appears after `staging`.

![](/assets/lab-3-stage-prod-created.png)
</details>

## 2. Add the three regions

Open `work/lab-3/stage-prod-regions.yaml`. It has three Stages. Replace the two `TODO`s in the first one, the other two are done for
you. Then apply it:

```sh
kargo apply -f work/lab-3/stage-prod-regions.yaml
```

<details>
<summary>What it does</summary>

Each region is a Stage with one step: `argocd-update`, which asks Argo CD to sync the application of that region and waits until it is
healthy. The Git change was already made by `prod`.

Each region takes Freight from `prod` and **follows** it: whatever Freight `prod` has, the region takes the same one. That is the
`MatchUpstream` policy.

Our applications also sync on their own when Git changes, so a page can change a few seconds before its Promotion is marked done.
</details>

<details>
<summary>Hint</summary>

- The Stage before a region is `prod`.
- The two policies you can choose from are `NewestFreight` and `MatchUpstream`. A region must not take the newest Freight on its own: it
  must take what `prod` has.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms three Stages. In the Kargo UI, three regions appear after `prod`, side by side: this is the fan-out.

![](/assets/lab-3-region-stages-created.png)

</details>

## 3. Let the regions follow by themselves

Open `work/lab-3/project-config.yaml` and replace the `TODO`. Then apply it:

```sh
kargo apply -f work/lab-3/project-config.yaml
```

<details>
<summary>What it does</summary>

It is the same file as in Lab 2, with a second policy: auto-promotion on for the regions. A pattern picks the three of them with one line,
so a fourth region would be covered without changing the file.

`prod` is not in the policy, so it stays a gate.
</details>

<details>
<summary>Hint</summary>

- A pattern starts with `glob:` or `regex:`.
- The names of the regions all start with `prod-`. The name `prod` has no dash, so it does not match.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the ProjectConfig. Nothing moves yet: `prod` has not received anything.
</details>

## 4. Ship 1.2.0 to staging

Pretend the developers have just shipped version 1.2.0. Run:

```sh
make release VERSION=1.2.0
kargo get promotions --project guestbook --stage dev
```

Run the second command again until the new Promotion on `dev` shows **Succeeded**. Then send the release to `staging`, which is still a gate:

```sh
kargo promote --project guestbook --stage staging --warehouse app
kargo get promotions --project guestbook --stage staging
```

Run the last command again until the Promotion has finished.

<details>
<summary>What it does</summary>

`make release` lets Kargo see 1.2.0, and `dev` takes it by itself, as in Lab 2. Then you promote it to `staging` by hand.
</details>

<details>
<summary>What you should see</summary>

`dev` and then `staging` show **v1.2.0**. Production is still on v0.9.0.

![](/assets/lab-3-promotion-to-stage.png)
</details>

## 5. Promote to production

One command, for the whole of production:

```sh
kargo promote --project guestbook --stage prod --warehouse app
kargo get promotions --project guestbook
```

Run the second command again until you see a Promotion on `prod` and then one on each region, all **Succeeded**.

<details>
<summary>What it does</summary>

The first command promotes 1.2.0 to `prod`. Kargo changes the three values files in one commit. When `prod` has the Freight, each region
takes the same Freight by itself, and syncs its application.
</details>

<details>
<summary>What you should see</summary>

Four Promotions: `prod` first, then `prod-amer-east`, `prod-amer-west` and `prod-emea`. You made one of them.

![](/assets/lab-3-promoted-to-prod.png)

Open the three regions. Each banner says **v1.2.0**:

- `http://guestbook-prod-amer-east.localtest.me`
- `http://guestbook-prod-amer-west.localtest.me`
- `http://guestbook-prod-emea.localtest.me`

</details>

<details>
<summary>What just happened</summary>

One decision, three deployments, one place to see it. `prod` wrote to Git, and each region followed and synced. If a region were the one
that failed, you would see it alone in the pipeline.
</details>

## 6. Check your work

Run:

```sh
make check STEP=3
```

<details>
<summary>What it does</summary>

Checks that `prod` and the three regions exist, that the regions have a policy, that each of them had a successful Promotion, and that
`staging` and the three regions run 1.2.0 in Git and in the cluster. It also tells you if a `TODO` is left in your files.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1, 2 and 3 for you, and you can read the finished files in `steps/3/`:

```sh
make catchup STEP=3
```

## Stuck?

- **The Promotion to `staging` or `prod` finds nothing to promote:** the Stage before it has not finished. Wait for its Promotion to
  succeed, then try again.
- **`prod` or a region shows v1.1.0, not v1.2.0:** you promoted a few seconds too early, when only the old Freight could go there. Run
  `kargo get freight --project guestbook`, take the alias of the newest Freight (the one with the smallest age), and promote it:
  `kargo promote --project guestbook --freight-alias <alias> --stage prod`.
- **The regions do not move after `prod`:** look at `kargo get projectconfig --project guestbook -o yaml`. There must be a policy for the
  regions, with `autoPromotionEnabled: true`.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses a file:** compare it with the example above. Indentation matters in YAML.
