# Lab 8 - Automatic rollback

**Goal:** a broken release must not wait for a person. In Lab 4 you rolled back by hand. Now you ask Kargo to do it, and you see the same
failure end with nobody touching anything. It takes about 15 minutes.

This lab uses **Kargo Enterprise** features: automatic rollback is part of Kargo on the Akuity Platform.

Before you start, finish Lab 7. `make check STEP=7` should say `All good.` If it does not, run `make catchup STEP=7`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- The **stable Freight** of a Stage is the last piece of Freight that passed its check there. Kargo remembers it for every Stage.
- An **automatic rollback** is a Promotion that Kargo creates by itself, when the check of a new Freight fails, to put the stable Freight
  back.
- Like a rollback by hand, it puts a **hold** on auto-promotion, so that Kargo does not try the broken Freight again.

Know more: [Working with Projects](https://docs.kargo.io/user-guide/how-to-guides/working-with-projects), in the part about automatic
rollbacks.

## 1. Turn on the rollback

Copy the starting file to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-8 work/
```

Open `work/lab-8/project-config.yaml`. It is the ProjectConfig you know, with a new block for `dev`. Replace the `TODO`, then apply it:

```sh
kargo apply -f work/lab-8/project-config.yaml
```

<details>
<summary>What it does</summary>

The policy of `dev` already said that it promotes by itself. Now it also says what to do when a check fails: go back to the stable Freight.

You choose which results of a check count. `Failed` means the check ran and said no. `Error` means the check could not run at all.
</details>

<details>
<summary>Hint</summary>

The check of `dev` that you wrote in Lab 4 fails when the page is not the guestbook. That result is called `Failed`.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the ProjectConfig. Nothing else happens: `dev` runs a version that passed its check, so there is nothing to go back from.
</details>

## 2. Break dev again

Use the same broken version as in Lab 4. Find the alias of 1.3.0 with `make freight`, and promote it to `dev` by hand:

```sh
make freight
kargo promote --project guestbook --freight-alias <alias of 1.3.0> --stage dev
kargo get promotions --project guestbook --stage dev
```

You can also do this in the Kargo UI, as in the previous labs.

Run the last command again every few seconds, for about a minute.

<details>
<summary>What it does</summary>

It is the same promotion as in Lab 4. The new Freight goes to `dev`, and the check runs against the page, which is not the guestbook.
</details>

<details>
<summary>What you should see</summary>

The Promotion of 1.3.0 is **Succeeded**. Then, about ten seconds later, **a new Promotion appears that you did not create**, and it
also goes to **Succeeded**. It sends the Freight that `dev` had before, 1.4.0, back to `dev`.

![](/assets/lab-8-rollback.png)

Check the stage and the page:

```sh
kargo get stages --project guestbook
```

`dev` says **Freight has been verified** again, and `http://guestbook-dev.localtest.me` says **v1.4.0**. For a few seconds before that, it
showed the error page of 1.3.0.

</details>

## 3. See who did it

You did not run a rollback. Ask Kargo who did:

```sh
kargo get promotions --project guestbook --stage dev -o yaml | grep -B3 -A3 'rollback'
kargo get stage dev --project guestbook -o yaml | grep -A8 autoPromotionHolds
```

<details>
<summary>What it does</summary>

The first command shows the Promotions of `dev` as Kargo stores them. The second shows the hold on auto-promotion.
</details>

<details>
<summary>What you should see</summary>

One Promotion has the annotation `kargo.akuity.io/rollback: "true"`: it is the one Kargo created. It also carries the annotation of the
hold, and the second command shows the hold on `dev`, for the Freight of the rollback.

![](/assets/lab-8-rollback-1.png)

If your inbox from Lab 7 is still set up, look at it: a message arrived for the rollback Promotion too.

</details>

<details>
<summary>What just happened</summary>

The same failure as in Lab 4, and this time nobody touched it. The check said no, Kargo promoted the stable Freight, and the hold kept it
from trying 1.3.0 again. The time between the failure and a working `dev` is a few seconds, and it does not depend on somebody noticing.

Two limits to remember. A Stage that has never passed a check has no stable Freight to go back to. And Kargo ignores failures older than
20 minutes, so a rollback is for something that just broke.
</details>

## 4. Resume

Like in Lab 4, the hold stays until you decide. Resume auto-promotion by promoting what Kargo would have picked:

```sh
kargo promote --project guestbook --stage dev --warehouse app
kargo get stage dev --project guestbook -o yaml | grep -c autoPromotionHolds
```

You can do this in the Kargo UI too.

<details>
<summary>What you should see</summary>

The Promotion goes to **Succeeded**, `dev` says **Freight has been verified**, and the second command prints `0`: the hold is gone.
</details>

## 5. Check your work

Run:

```sh
make check STEP=8
```

<details>
<summary>What it does</summary>

Checks that the project has a rollback policy, that 1.3.0 was never verified in `dev`, that `dev` has a rollback Promotion made by Kargo,
that the hold is gone, and that `dev` runs the newest version in Git and in the cluster. It also tells you if a `TODO` is left in your file.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 8 for you, and you can read the finished file in `steps/8/`:

```sh
make catchup STEP=8
```

## Stuck?

- **No rollback appears:** wait a minute. Then look at `kargo get projectconfig --project guestbook -o yaml`: `dev` must have an
  `autoRollback` with `Failed`. Also check that the check of 1.3.0 really failed: `dev` must say that a metric failed.
- **The rollback itself fails:** if a rollback Promotion fails, Kargo does not create another one for that Freight. Look at the steps of the
  Promotion in Kargo, fix what is wrong, and promote the stable Freight by hand.
- **`dev` does not take new versions any more:** that is the hold. Resume it (step 4).
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses the file:** compare it with the example above. Indentation matters in YAML.
