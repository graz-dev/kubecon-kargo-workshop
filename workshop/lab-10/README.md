# Lab 10 - Custom promotion steps

**Goal:** add to Kargo a step that it does not have. You turn on what custom steps need, register two of them, and run them in a promotion:
a greeting, and a security scan of the image that is about to be promoted. It takes about 20 minutes.

This lab uses **Kargo Enterprise** features, and custom steps are **alpha**: the details may change in future versions.

Before you start, finish Lab 9. `make check STEP=9` should say `All good.` If it does not, run `make catchup STEP=9`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- A **custom step** is a container image that Kargo can run as a step of a promotion. You register it once, with a name, and every
  project of the instance can use it.
- The **Promotion Controller** is the part of Kargo that runs promotions as pods. Custom steps need it: each of their containers runs in the
  pod of the promotion.
- Steps of one promotion share the same working folder, so a custom step can read what the steps before it wrote.

Know more: [Custom steps](https://docs.kargo.io/user-guide/reference-docs/custom-steps).

## 1. Turn on the Promotion Controller

Run:

```sh
make promotion-controller STATE=on
```

<details>
<summary>What it does</summary>

The command changes one setting of your Kargo instance, `promoControllerEnabled`, and waits for the controller to start.

From now on, every promotion of your instance runs in a pod of the Kargo agent that is in your kind cluster. Your agent is already
self-hosted, which custom steps also need.

It is a setting of the whole instance, so it also changes the promotions you already know. They take a few seconds longer, because a pod
has to start.
</details>

<details>
<summary>What you should see</summary>

A new component appears next to the agent in your cluster:

```sh
export KUBECONFIG=$PWD/.tools/kubeconfig
kubectl -n akuity get deploy | grep promotion-controller
```

It is called `kargo-promotion-controller-` followed by the name of your agent, and it is ready.
</details>

## 2. Register two steps

Copy the starting files to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-10 work/
```

Open `work/lab-10/custom-steps.yaml`. It defines two steps. Read the first one, `hello-world`, then replace the `TODO` in the second, and apply
the file:

```sh
kargo apply -f work/lab-10/custom-steps.yaml
```

<details>
<summary>What it does</summary>

Each step is an image and a command:

- `hello-world` runs `busybox`. It prints a message and gives it back to Kargo by writing to the file `$KARGO_OUTPUT`.
- `trivy-image` runs the Trivy scanner on an image and keeps the report. The report is what the step prints, and the key `log` makes it
  appear in the Logs tab of the Kargo UI.

The text between `${{` and `}}` is filled in with the **config** that the Stage gives to the step. Kargo does not check that the config has
the keys you ask for: a missing one is an error when the promotion runs.

A custom step is registered for the whole instance, not for one project. That is why only an administrator can do it.
</details>

<details>
<summary>Hint</summary>

The Stage will give the step a config called `image`. In the command, the config is written as `config.image`, inside `${{ }}`.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the two custom steps were created.

You can also see them in the settings of your Kargo instance in the UI:

![](/assets/lab-10-custom-steps.png)
</details>

## 3. Use them in dev

Open `work/lab-10/stage-dev.yaml`. It is your `dev` Stage with two new steps at the start of its promotion. Replace the two `TODO`s, apply it,
and promote:

```sh
kargo apply -f work/lab-10/stage-dev.yaml
kargo promote --project guestbook --stage dev --warehouse app
kargo get promotions --project guestbook --stage dev
```

Run the last command again every few seconds. The scan takes about a minute.

<details>
<summary>What it does</summary>

The scan comes **before** the steps that write to Git: if you decide later that a bad scan must stop the promotion, nothing has changed yet.
A custom step is used like any other: `uses`, a name with `as`, and its `config`.

The image to scan is the image of the Freight that is being promoted: the one of the vars, a colon, and the tag.
</details>

<details>
<summary>Hint</summary>

- The step that scans is the one you registered as `trivy-image`.
- The image with its tag is written like this: the image of the vars, then `:`, then `imageFrom(vars.image).Tag`.
</details>

<details>
<summary>What you should see</summary>

The Promotion is **Running** for about a minute and then **Succeeded**. Open it in the Kargo UI: the steps `hello` and `scan` come first.

- `hello` has the output `message: Hello from the dev promotion!`.
- `scan` has a Logs tab with the Trivy report of the image: a table with the vulnerabilities found and their severity.

To read the report in the terminal, use the name of the Promotion from the list:

```sh
kargo get promotion <promotion> --project guestbook -o yaml | grep -A12 'scan:'
```

You can also see it in the Kargo UI:

![](/assets/lab-10-custom-step-promoted.png)

</details>

<details>
<summary>What just happened</summary>

You added to Kargo something it did not have, without touching Kargo: an image and a command. The same way, a team can add a policy check, a
signature check or a call to an internal system, and every project of the instance gets it by name.

Remember the limits of an alpha feature. The step runs as the user 65532, so images that need another user do not work yet. The steps of a
promotion share one pod. And the command may run more than once if the step is retried, so it should be safe to repeat.
</details>

## 4. Extra: make the scan a gate

Until now the scan only reports. In `work/lab-10/custom-steps.yaml`, change `--exit-code=0` to `--exit-code=1`, apply the file again, and
promote `dev` once more:

```sh
kargo apply -f work/lab-10/custom-steps.yaml
kargo promote --project guestbook --stage dev --warehouse app
kargo get promotions --project guestbook --stage dev
```

<details>
<summary>What it does</summary>

With `--exit-code=1`, Trivy ends with an error when it finds vulnerabilities of the severities you asked for. The step fails, and a failed step
stops the promotion.
</details>

<details>
<summary>What you should see</summary>

After about a minute, the Promotion is **Failed**. In its steps, `hello` is **Succeeded**, `scan` is **Failed** with the report in its message,
and all the steps after it are **Skipped**: nothing was committed, nothing was pushed, and `dev` still runs what it ran before.

`dev` shows the error until the next promotion succeeds. Put `--exit-code=0` back, apply the file, and promote again to clear it.

![](/assets/lab-10-custom-step-promotion-fail.png)

</details>

## 5. Check your work

Run:

```sh
make check STEP=10
```

<details>
<summary>What it does</summary>

Checks that the Promotion Controller is on, that `dev` uses the two steps, and that a promotion of `dev` ran them: it kept the greeting and
the scan report. It also tells you if a `TODO` is left in your files.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 10 for you, and you can read the finished files in `steps/10/`. It turns on the Promotion
Controller too:

```sh
make catchup STEP=10
```

## Stuck?

- **Kargo says the step `trivy-image` does not exist:** register the steps first (step 2), and check that the Promotion Controller is on (step 1).
- **The Promotion stays Running for a long time:** the first scan downloads the vulnerability database, and the pod pulls the images. Give it
  two minutes, then look at the pod: `kubectl -n akuity get pods | grep promotion`.
- **The scan step fails:** open the step in the Kargo UI and read its output. A missing key in `config` is an error at that point.
- **The promotion fails at `git-push` with `could not read Username`:** the promotion pods have no permission to push. Run `make up` again.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses a file:** compare it with the example above. Indentation matters in YAML.
