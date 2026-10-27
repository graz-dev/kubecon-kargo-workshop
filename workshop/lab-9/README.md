# Lab 9 - Governance

**Goal:** prove who approved what. You close the door to production with a freeze, then open it only for a promotion that gives a reason, gets
an approval, and leaves a record. It takes about 20 minutes.

This lab uses **Kargo Enterprise** features: promotion windows, approvals, forms and audit events are part of Kargo on the Akuity
Platform. The approval, form and audit steps are marked **Beta** in the docs.

Compare with Lab 5: there, a merged pull request was the approval, and Kargo did not know who gave it. Here the approval is **recorded**.

Before you start, finish Lab 8. `make check STEP=8` should say `All good.` If it does not, run `make catchup STEP=8`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- A **promotion window** says when promotions are allowed or forbidden for a Stage. A **Deny** window is a freeze. A freeze wins over
  everything else, and it blocks promotions by hand, automatic promotions and automatic rollbacks.
- An **approval** is a promotion step that waits until a person says yes in the Kargo UI.
- An **audit event** is a line that Kargo writes in the log when a promotion says so: who did what, and why. It is kept centrally.

Know more: [Promotion windows](https://docs.kargo.io/user-guide/how-to-guides/promotion-windows),
[`wait-for-approval`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/wait-for-approval),
[`get-user-input`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/get-user-input) and
[`record-audit-event`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/record-audit-event).

## 1. Freeze production

Copy the starting files to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-9 work/
```

Open `work/lab-9/project-config.yaml`. It is the ProjectConfig of Lab 8 with a window for `prod`. Replace the two `TODO`s so that the
freeze is **on**, then apply it and try to promote to `prod`:

```sh
kargo apply -f work/lab-9/project-config.yaml
kargo promote --project guestbook --stage prod --warehouse app
```

<details>
<summary>What it does</summary>

The window is called `workshop-freeze`. It repeats every day from midnight to the last second of the day, in UTC, so it is open for
practically nothing: production is frozen. Only `prod` is named. The regions are not, because they follow `prod`.
</details>

<details>
<summary>Hint</summary>

- The two kinds of window are `Allow` and `Deny`. Which one forbids?
- `disabled` switches a window off without deleting it. For a freeze that is on, it is `false`.
</details>

<details>
<summary>What you should see</summary>

You can see the promotion windows in the Kargo UI, in the settings of the project:

![](/assets/lab-9-promotion-windows.png)

Kargo refuses the promotion. The error says that the promotion is not permitted at this time, names your window, and says when
promotions resume:

```
promotion of Stage "prod" is not permitted at this time: Promotion freeze "workshop-freeze" is active; promotions resume at ...
```

Nothing was created: there is no Promotion waiting to be cleaned up. In the Kargo UI, the Stage `prod` tells why it is closed.

![](/assets/lab-9-promotion-windows-2.png)

</details>

Now lift the freeze. In the same file, change `disabled` to `true`, and apply it again:

```sh
kargo apply -f work/lab-9/project-config.yaml
```

<details>
<summary>What it does</summary>

There is no way around a freeze: not for a manual promotion, not for an automatic one. The only way to open the door is to change the
window, and that is a change of the ProjectConfig, which only people with the right to edit it can make.
</details>

## 2. Ask for a reason and an approval

Open `work/lab-9/stage-prod.yaml`. It is your `prod` Stage with three new steps: a form, an approval, and a record. Read them, then replace
the two `TODO`s in the last one and apply it:

```sh
kargo apply -f work/lab-9/stage-prod.yaml
```

<details>
<summary>What it does</summary>

The promotion of `prod` now does this:

1. `get-user-input` asks a question in the Kargo UI, with a form: *Why does this version go to production?*
2. `wait-for-approval` waits until one person approves. The promotion stays **Running** meanwhile.
3. The usual steps change the three regions in Git.
4. `record-audit-event` writes down who approved and why.

Each step has a name (`as:`), as in Lab 5. The steps after it can use what it produced: who approved, and what was written in the form.
</details>

<details>
<summary>Hint</summary>

- The approval step is called `approve`, and its answers are in `responses`. The first one is `outputs.approve.responses[0]`, and the person
  is its `user`. Look at the `message` line: it already uses it.
- The form step is called `reason`, and the field in its form is also `reason`: what the person wrote is `outputs.reason.values.reason`.
- Write them inside `${{ }}`.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the Stage.
</details>

## 3. Promote, answer, approve

Production already runs 1.4.0, so promote it again: a redeploy is a change to production too. You can also do this directly in the Kargo UI.

```sh
kargo promote --project guestbook --stage prod --warehouse app
kargo get promotions --project guestbook --stage prod
```

The Promotion is **Running**: it is waiting for you. Open the Kargo UI, project `guestbook`, and open the Promotion. Write a reason in the
form and submit it. Then approve.

![](/assets/lab-9-promotion-approval.png)
![](/assets/lab-9-promotion-approval-1.png)

<details>
<summary>What it does</summary>

The first step shows a form with your question. When you submit it, the second step shows the approval, with **Approve** and **Reject**.
You may approve your own promotion here, because in your project you are the only user. In a real team, you would limit who can approve.
</details>

<details>
<summary>What you should see</summary>

After the form and the approval, the Promotion goes to **Succeeded** in a few seconds. Nothing changes in the regions: they already ran
1.4.0. What matters is what Kargo wrote down.

![](/assets/lab-9-promotion-approved.png)

</details>

## 4. Read the audit

Ask for the audit events of your project:

```sh
make audit
```

<details>
<summary>What it does</summary>

Lists the audit events of your project: when, who, what, which Stage, and the message of the step.
</details>

<details>
<summary>What you should see</summary>

A line like this, and under it, what you wrote in the form:

```
WHEN                  WHO      WHAT      STAGE    MESSAGE
2026-10-27T15:31:14   admin    approved  prod     Release 1.4.0 to prod approved by admin.
                                                 {"reason":"<what you wrote>"}
```

You can see the same in the Events tab of the project in the Kargo UI.

![](/assets/lab-9-events.png)
</details>

<details>
<summary>What just happened</summary>

Who approved, when, and why, stored by Kargo and not by a chat message. Compare it with Lab 5: a merged pull request says that
somebody pressed Merge. This says who approved a promotion, with the reason they gave, as a step of the promotion itself.
</details>

## 5. Check your work

Run:

```sh
make check STEP=9
```

<details>
<summary>What it does</summary>

Checks that the project has a freeze window on `prod` and that it is lifted, that `prod` has the three steps, that a promotion to `prod` was
approved, and that the audit event was recorded. It also tells you if a `TODO` is left in your files.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 9 for you, and you can read the finished files in `steps/9/`. It answers the form and gives
the approval itself, with your user, because a script cannot click in the UI:

```sh
make catchup STEP=9
```

## Stuck?

- **The promotion to `prod` is refused:** the freeze is on. Set `disabled` to `true` in `work/lab-9/project-config.yaml` and apply it.
- **The promotion stays Running:** it is waiting for you. Open it in the Kargo UI, answer the form, and approve.
- **There is no form in the Kargo UI:** check that you applied `work/lab-9/stage-prod.yaml`, and that you promoted after that.
- **The last step fails:** look at the steps of the promotion in Kargo. The names of the steps must be `approve` and `reason`.
- **`make audit` says there are no events:** the promotion did not reach its last step. Wait for it to succeed.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses a file:** compare it with the example above. Indentation matters in YAML.
