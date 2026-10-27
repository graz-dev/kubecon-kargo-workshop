# Lab 6 - Kargo finds the releases

**Goal:** remove the last bit of make-believe. Until now, `make release` told your Warehouse when a version was "shipped". Now the
Warehouse watches the registry by itself. A developer pushes a new image, and you follow it all the way to production. It takes about
20 minutes.

You work with the **Kargo CLI** and with **Gitea** in your browser, as in Lab 5. This time you also see how to promote from the Kargo UI.

Before you start, finish Lab 5. `make check STEP=5` should say `All good.` If it does not, run `make catchup STEP=5`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- An **image selection strategy** is the rule a Warehouse uses to choose *the* image among all the tags it sees. Until now we used
  `SemVer`: the highest version in a range, with a fence at the top. `NewestBuild` chooses the image that was **built most recently**.
- **Discovery** is how a Warehouse looks at the registry. It does it every few minutes. A webhook can make it instant, and
  `kargo refresh` asks it to look right now.

Know more: [Working with Warehouses](https://docs.kargo.io/user-guide/how-to-guides/working-with-warehouses).

## 1. Take the fence away

Copy the starting file to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-6 work/
```

Open `work/lab-6/warehouse.yaml`, replace the `TODO`, and apply it:

```sh
kargo apply -f work/lab-6/warehouse.yaml
make freight
```

<details>
<summary>What it does</summary>

It is your Warehouse again, with three differences in the image subscription:

- **The strategy.** No more version range and no more fence at 1.3.1: the Warehouse takes the image built most recently.
- **The tags.** Only tags that look like a version are considered.
- **The cache.** Our tags never change, so Kargo does not need to read the same image twice.

From now on, `make release` is not needed any more. It has done its job.
</details>

<details>
<summary>Hint</summary>

The strategy is named after what it looks for: the newest build. It is written as one word, with two capital letters. Open the "Know more" link if you want the full list.
</details>

<details>
<summary>What you should see</summary>

Nothing changes: `make freight` shows the same Freight as before. The newest image is still 1.3.1, which `dev` already runs.
</details>

## 2. A developer ships

Pretend a developer has just merged a change, and their pipeline has built and pushed a new image. **The instructor publishes it now.**
Wait for the signal.

Then ask your Warehouse to look at the registry, and see what it found:

```sh
kargo refresh warehouse --project guestbook app
make freight
kargo get promotions --project guestbook --stage dev
```

Run the last two commands again until the new version appears in `dev`. If nothing shows up after a minute, run the first one again.

<details>
<summary>What it does</summary>

The Warehouse looks at the registry, finds an image built after 1.3.1, and makes Freight from it. Without `kargo refresh` it would have
found it too, at its next visit, in a few minutes.

Auto-promotion is still on for `dev`, so Kargo promotes the new Freight there by itself, and runs the check you wrote in Lab 4.
**Nobody announced this release to Kargo.**
</details>

<details>
<summary>What you should see</summary>

A new piece of Freight with the version **1.4.0**, and a new Promotion on `dev` that goes to **Succeeded**. A few seconds later `dev` says
**Freight has been verified**.

![](/assets/lab-6-new-version.png)

Open `http://guestbook-dev.localtest.me`: the banner is orange and says **v1.4.0**.

![](/assets/lab-6-new-version-2.png)

</details>

## 3. Through staging

`staging` is still the gate with the pull request. Promote the new Freight and approve it, as in Lab 5:

```sh
kargo promote --project guestbook --stage staging --warehouse app
```

You can also do this with the **Promote** or **Promote from upstream** button on the `staging` Stage:

![](/assets/lab-6-promote-staging.png)
![](/assets/lab-6-promote-staging-2.png)
![](/assets/lab-6-waiting-for-PR.png)

Open the pull request in Gitea at `http://gitea.localtest.me`, read the change, and merge it. Then:

```sh
kargo get promotions --project guestbook --stage staging
```

<details>
<summary>What you should see</summary>

The Promotion waits, then goes to **Succeeded** within about 15 seconds of the merge. `staging` says **Freight has been verified** after the
end-to-end test, and `http://guestbook-staging.localtest.me` says **v1.4.0**.

![](/assets/lab-6-staging-promoted.png)

</details>

## 4. To production

One more decision, as in Lab 3:

```sh
kargo promote --project guestbook --stage prod --warehouse app
kargo get promotions --project guestbook
```

You can also do this in the Kargo UI, as in the previous step.

Run the second command again until `prod` and the three regions are **Succeeded**.

<details>
<summary>What you should see</summary>

![](/assets/lab-6-prod-promoted.png)

The three regions follow `prod` by themselves. Each banner says **v1.4.0**:

- `http://guestbook-prod-amer-east.localtest.me`
- `http://guestbook-prod-amer-west.localtest.me`
- `http://guestbook-prod-emea.localtest.me`
</details>

<details>
<summary>What just happened</summary>

Look at what you did, and what you did not do. A push to the registry was found by Kargo. `dev` took it and checked it, with no human.
`staging` waited for a pull request. `prod` waited for you, and the regions followed. You never typed `make release`.

This is the loop of a real team: **automatic where it is safe, a person where it matters.**
</details>

## 5. Check your work

Run:

```sh
make check STEP=6
```

<details>
<summary>What it does</summary>

Checks that the Warehouse follows the registry, that Kargo found a version newer than 1.3.1, that this version went through `dev`,
`staging`, `prod` and the three regions, that its pull request was opened and nothing is left waiting, and that Git and the applications
run it. It also tells you if a `TODO` is left in your file.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 6 for you, and you can read the finished file in `steps/6/`. It needs the new version to be
on the registry: if the instructor has not published it yet, it tells you to wait.

```sh
make catchup STEP=6
```

## Stuck?

- **The new Freight does not appear:** the instructor may not have published yet. When they have, run
  `kargo refresh warehouse --project guestbook app` and wait a few seconds.
- **`dev` does not take the new Freight:** look at `kargo get stage dev --project guestbook -o yaml | grep autoPromotionHolds`. If there is a
  hold, promote by hand to lift it: `kargo promote --project guestbook --stage dev --warehouse app`.
- **Kargo says the Warehouse is not valid:** compare your file with the example above. Indentation matters in YAML.
- **`make release` says there is no release to announce:** that is right. The Warehouse follows the registry now.
- **`make check` says a `TODO` is left:** it tells you the line.
