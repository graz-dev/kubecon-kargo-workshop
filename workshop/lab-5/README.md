# Lab 5 - A pull request as approval

**Goal:** make `staging` wait for a person. Kargo opens a pull request in Gitea and waits. When someone merges it, the promotion goes on.
It takes about 15 minutes.

You work with the **Kargo CLI**, and with **Gitea** in your browser: this is where you approve.

Before you start, finish Lab 4. `make check STEP=4` should say `All good.` If it does not, run `make catchup STEP=4`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- A **pull request** (PR) asks to merge one Git branch into another, and gives people a place to review the change first.
- With a PR as approval, Kargo does not push to `main`. It pushes to a **new branch**, opens the PR, and **waits**. Nothing reaches
  `main`, and so nothing reaches Argo CD, until somebody merges.
- Each step of a promotion can give a name to its result (`as:`), and the steps after it can use what it produced: the branch that was
  pushed, the number of the PR. These are the **outputs** of a step.

Know more: [`git-open-pr`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/git-open-pr),
[`git-wait-for-pr`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/git-wait-for-pr) and
[Expressions](https://docs.kargo.io/user-guide/reference-docs/expressions).

## 1. Build the gate

Copy the starting file to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-5 work/
```

Open `work/lab-5/stage-staging.yaml`. It is your `staging` Stage with new steps. Replace the three `TODO`s, then apply it:

```sh
kargo apply -f work/lab-5/stage-staging.yaml
```

<details>
<summary>What it does</summary>

The promotion of `staging` now does this:

1. `git-clone`, `yaml-update` and `git-commit` prepare the change, as before.
2. `git-push` sends it to a branch that Kargo names for you, not to `main`.
3. `git-open-pr` opens a pull request from that branch into `main`.
4. `git-wait-for-pr` waits until the pull request is merged or closed. This is the approval.
5. `argocd-update` syncs the application, as before.

Look at the lines that start with `if:`. If there is nothing to commit, for example because `staging` already has that version, the
steps that follow are skipped: there is nothing to approve.

The verification you wrote in Lab 4 is still there. After the merge, the end-to-end test runs.
</details>

<details>
<summary>Hint</summary>

- Kargo can make up the name of the branch: ask for it in `git-push`.
- A step with `as: push` gives its results to the steps after it, under `outputs['push']`. The push step produces the name of the branch.
- A step with `as: open-pr` produces `pr.id`, the number of the pull request.
- Write them inside `${{ }}`, like the image tag in Lab 1.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the Stage.
</details>

## 2. Promote, and wait

Version 1.3.1 is verified in `dev`, so `staging` can take it. Run:

```sh
kargo promote --project guestbook --stage staging --warehouse app
kargo get promotions --project guestbook --stage staging
```

<details>
<summary>What it does</summary>

It creates a Promotion to `staging`. Kargo prepares the change, pushes the branch and opens the pull request. Then it stops and waits.
</details>

<details>
<summary>What you should see</summary>

After a few seconds, the Promotion is **Running**, and it stays Running. It is not stuck: it is waiting for you.

![](/assets/lab-5-promotion-waiting.png)

In the Kargo UI, you can also see the PR waiting for approval:

![](/assets/lab-5-promotion-waiting-2.png)

Open `http://guestbook-staging.localtest.me`: it still says v1.2.0.

</details>

## 3. Review and merge

You are the approver. Open Gitea at `http://gitea.localtest.me` and sign in. `make urls` prints your user and password. Then:

1. Open the repository `workshop/guestbook-gitops`, and **Pull requests**.
2. Open the pull request **Promote guestbook 1.3.1 to staging**.

![](/assets/lab-5-PR.png)

3. In **Files changed**, read the change. It should be one line.

![](/assets/lab-5-pr-changes.png)

4. Go back to **Conversation** and click **Create merge commit**, then confirm.

Then look at Kargo:

```sh
kargo get promotions --project guestbook --stage staging
kargo get stages --project guestbook
```

<details>
<summary>What it does</summary>

The merge puts the change in `main`. Kargo checks Gitea every few seconds, sees the merge, finishes the Promotion, and Argo CD updates
`staging`. Then the end-to-end test runs.
</details>

<details>
<summary>What you should see</summary>

Within about 15 seconds, the Promotion is **Succeeded**. A little later `staging` says **Freight has been verified**.

Open `http://guestbook-staging.localtest.me`: the banner says **v1.3.1**.

![](/assets/lab-5-staging-promoted.png)

</details>

<details>
<summary>What just happened</summary>

Merging is the approval. It is simple and it lives in Git, where your team already works: reviewers, comments, history.

Remember what it does not record. Kargo only knows that the PR was merged. It does not know who approved, or whether the person who
opened it also merged it. Hold on to that for later.
</details>

## 4. Check your work

Run:

```sh
make check STEP=5
```

<details>
<summary>What it does</summary>

Checks that `staging` has the pull request gate, that Kargo opened a pull request and that it was merged, that no pull request is still
waiting, that 1.3.1 is verified in `staging`, and that Git and the application have 1.3.1. It also tells you if a `TODO` is left in your
file.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 5 for you, and you can read the finished file in `steps/5/`. It merges the pull request for
you:

```sh
make catchup STEP=5
```

## Stuck?

- **The Promotion stays Running:** it is waiting for the pull request. Open it in Gitea and merge it.
- **The Promotion failed with `pull request … was closed without being merged`:** someone closed the pull request instead of merging
  it. Nothing changed in `main`. Promote again to get a new one: `kargo promote --project guestbook --stage staging --warehouse app`.
- **The Promotion failed in `git-push` with `could not read Username`:** Kargo has no permission to push. Run `make up` again.
- **I cannot sign in to Gitea:** `make urls` prints the user and the password.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses the file:** compare it with the example above. Indentation matters in YAML.
