# Lab 4 - Verification and rollback

**Goal:** make Kargo check every release after it is promoted, see what happens when a release is broken, and go back. It takes about
20 minutes.

You work with the **Kargo CLI**, and this time the Kargo UI is worth opening too: it shows the checks and their logs.

Before you start, finish Lab 3. `make check STEP=3` should say `All good.` If it does not, run `make catchup STEP=3`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- **Verification** is a check that Kargo runs after a promotion. A piece of Freight only counts as **verified** in a Stage if the check
  passes, and Stages after it only take verified Freight.
- An **AnalysisTemplate** describes the check. Ours is a small Job: a container that calls the application and passes or fails.
- A **rollback** in Kargo is not a special operation. It is a promotion of Freight the Stage already had.
- A **hold** pauses auto-promotion on a Stage when someone promotes by hand, so that Kargo does not undo the choice.

Know more: [Verification](https://docs.kargo.io/user-guide/how-to-guides/working-with-stages) in Working with Stages and
[Analysis](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/) in Argo Rollouts.

## 1. Write the checks

Copy the starting files to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-4 work/
```

Open `work/lab-4/analysis.yaml`. It has two checks: a smoke test for `dev` and an end-to-end test for `staging`. Replace the `TODO` in the
smoke test. Then apply it:

```sh
kargo apply -f work/lab-4/analysis.yaml
```

<details>
<summary>What it does</summary>

Each check starts a Job that calls the application at its address inside the cluster and looks at the home page. If the page does not
contain the text we expect, the Job fails, and so does the check.

The smoke test only asks: is our guestbook answering? The end-to-end test asks a bit more: is the entry form on the page?
</details>

<details>
<summary>Hint</summary>

The home page of the guestbook has a title. Open `http://guestbook-dev.localtest.me` and read it. It is the same text the end-to-end test
looks for.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the two AnalysisTemplates were created.
</details>

## 2. Turn them on

A check does nothing until a Stage uses it. Open `work/lab-4/stage-dev.yaml`: it is your `dev` Stage with a new `verification` block at the
end. Replace the `TODO` with the name of the smoke test. `work/lab-4/stage-staging.yaml` is ready: it uses the end-to-end test.

Apply both, then ask Kargo to check what `dev` runs now:

```sh
kargo apply -f work/lab-4/stage-dev.yaml
kargo apply -f work/lab-4/stage-staging.yaml
kargo verify stage dev --project guestbook
kargo get stages --project guestbook
```

<details>
<summary>What it does</summary>

The `verification` block says which checks run after a promotion to that Stage, and with which arguments. Here the argument is the name of
the Stage, so the same check works for every Stage.

`kargo verify stage` runs the check once, now, on what the Stage has.
</details>

<details>
<summary>What you should see</summary>

A few seconds later, `dev` says **Freight has been verified** again.

The Job runs in your kind cluster, next to the Kargo agent. Take a look while it runs:

```sh
export KUBECONFIG=$PWD/.tools/kubeconfig
kubectl -n akuity get pods | grep smoke
```

In the Kargo UI, you should see a new verification on the `dev` Stage, with an `AnalysisRun`:

![](/assets/lab-4-first-manual-verification.png)

If you open the `AnalysisRun`, you can see the checks that ran:

![](/assets/lab-4-check-1.png)
![](/assets/lab-4-check-2.png)

</details>

## 3. A release that looks fine

Pretend the developers have just shipped version 1.3.0. Run:

```sh
make release VERSION=1.3.0
kargo get stages --project guestbook
```

Run the second command again until `dev` stops changing. It takes about a minute.

<details>
<summary>What it does</summary>

`make release` lets Kargo see 1.3.0, and `dev` takes it by itself, as in Lab 2. After the promotion, `dev` runs its check.
</details>

<details>
<summary>What you should see</summary>

The promotion to `dev` is **Succeeded**, but `dev` is not ready: its status says the check **failed**, with a message like
`Metric "smoke-test" assessed Failed`.

Open `http://guestbook-dev.localtest.me`. The server answers, and Argo CD says the application is Healthy. The page, though, is an error
page. **Healthy is not the same as correct.** Only the check noticed.

![](/assets/lab-4-error-page.png)

See the log of the check. Kubernetes deletes the finished pod after ten minutes, so do it soon:

```sh
kubectl -n akuity get pods | grep smoke
kubectl -n akuity logs <the newest smoke-test pod>
```

You can also open the Kargo UI to see the status of the Promotion and the logs of the verification:

![](/assets/lab-4-verification-failure.png)
![](/assets/lab-4-verification-failure-2.png)

</details>

Now try to push the broken release forward. Find the alias of 1.3.0 with `make freight` (or check the Kargo UI), and run:

```sh
kargo promote --project guestbook --freight-alias <alias of 1.3.0> --stage staging
```

<details>
<summary>What you should see</summary>

Kargo refuses: the Freight **is not available to Stage "staging"**. Freight that fails its check in `dev` cannot go on. `staging` and
production still run 1.2.0.

`make freight` lists every piece of Freight with its version, where it is now, and where it is verified. The 1.3.0 line has `dev` under
"IN NOW" and nothing under "VERIFIED IN". You can see the same in the Kargo UI.
</details>

## 4. Roll back

`dev` runs a broken release. Put the previous one back: promote the Freight that `dev` had before. Find its alias with `make freight`
(version 1.2.0) or check the Kargo UI, and run:

```sh
make freight
kargo promote --project guestbook --freight-alias <alias of 1.2.0> --stage dev
kargo get stages --project guestbook
```

<details>
<summary>What it does</summary>

It is a normal promotion, of Freight the Stage already knew. **Rollback is just promoting older Freight.** There is no emergency path.
</details>

<details>
<summary>What you should see</summary>

A few seconds later `dev` is ready again and says **Freight has been verified**. Open `http://guestbook-dev.localtest.me`: the banner says
**v1.2.0**.

In the Kargo UI, you should see the older version on `dev`, with the alert "Auto-promotion paused":

![](/assets/lab-4-rollback.png)
![](/assets/lab-4-rollback-2.png)

</details>

## 5. The fix, and the hold

The developers fix the bug and ship 1.3.1. Run:

```sh
make release VERSION=1.3.1
make freight
```

Wait a minute, then run `make freight` again.

<details>
<summary>What you should see</summary>

The Freight 1.3.1 exists, but it is in **no Stage**: `dev` did not take it, even though auto-promotion is on.

![](/assets/lab-4-autopromotion-hold.png)

That is the hold. You promoted by hand, so Kargo does not promote by itself on `dev` until you decide. Your choice sticks. You can see it
with:

```sh
kargo get stage dev --project guestbook -o yaml | grep -A8 autoPromotionHolds
```
</details>

Resume auto-promotion by promoting what Kargo would have picked:

```sh
kargo promote --project guestbook --stage dev --warehouse app
kargo get stages --project guestbook
```

You can also do this with the **Resume** button in the UI.

<details>
<summary>What it does</summary>

With `--warehouse`, Kargo picks the newest Freight that `dev` can take, which is 1.3.1. Promoting it lifts the hold.
</details>

<details>
<summary>What you should see</summary>

`dev` takes 1.3.1, runs the check, and says **Freight has been verified**. The banner on `http://guestbook-dev.localtest.me` says
**v1.3.1**. The hold is gone: the command above prints nothing.

![](/assets/lab-4-fixed-version-promoted.png)
</details>

<details>
<summary>What just happened</summary>

Kargo found the broken release because a check said so, and kept it from going past `dev`. You went back with a normal promotion, and a
hold kept your choice until you lifted it.
</details>

## 6. Check your work

Run:

```sh
make check STEP=4
```

<details>
<summary>What it does</summary>

Checks that `dev` and `staging` have their checks, that 1.3.0 was never verified, that `dev` has a failed verification in its history,
that 1.3.1 is verified and the hold is gone, and that `staging` and production never moved from 1.2.0. It also tells you if a `TODO` is left
in your files.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 4 for you, and you can read the finished files in `steps/4/`:

```sh
make catchup STEP=4
```

## Stuck?

- **The check passes for 1.3.0, so nothing fails:** the text in your smoke test is too generous. It must appear on the real home page, and
  not on the error page.
- **Nothing happens after `kargo verify stage`:** give it 30 seconds, then look at `kubectl -n akuity get pods | grep smoke`. If no pod
  appears, send the output to the organizers.
- **Kargo refuses the rollback because the Freight is not available:** use the alias of 1.2.0 from `make freight`, and not the one of 1.3.0.
- **`dev` does not take 1.3.1:** that is the hold. Run `kargo promote --project guestbook --stage dev --warehouse app`.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses a file:** compare it with the example above. Indentation matters in YAML.
