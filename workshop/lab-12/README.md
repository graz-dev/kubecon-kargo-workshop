# Lab 12 - A change request

**Goal:** let production wait for the change process your company already has. The promotion of `prod` will open a change request in
ServiceNow, wait until it is approved, change the three regions, and close the change request. It takes about 20 minutes.

This lab uses **Kargo Enterprise** features: the ServiceNow steps.

Compare with Lab 9: there, the approval was a click in the Kargo UI. Here the approval happens in ServiceNow, where the people who approve
changes already work. Kargo only waits for it.

Before you start, finish Lab 11. `make check STEP=11` should say `All good.` If it does not, run `make catchup STEP=11`. In a new terminal,
run `export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

If you did the extra of Lab 11, this lab replaces your `prod` Stage: the Terraform steps of `prod` go away, and the addresses of the
Lambda that are already in Git stay.

## The words of this lab

- **ServiceNow** is a system that many companies use to manage IT work, including changes to production.
- A **change request** is a ticket that asks permission to change production. It has a number, such as `CHG0030035`, and a **state**: it
  starts as *Authorize* and has to be approved before anyone may implement it.
- The **Change Advisory Board** is the group of people who approve changes.
- **Implement** is the state of a change that may happen now. In the `state` field of ServiceNow it is `-1`.

Know more: [`snow-create`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/snow-create),
[`snow-wait-for-condition`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/snow-wait-for-condition) and
[`snow-update`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/snow-update).

## 1. Give Kargo the ServiceNow credentials

The instructor gives you three things: the address of ServiceNow, a user, and its password. Kargo keeps them in a Secret and uses them only
when a promotion talks to ServiceNow. First, run these three lines, **one at a time**. Each one tells you what to paste: paste it and press
Enter. The password does not appear on the screen while you paste, so do not worry.

```sh
printf 'ServiceNow address: '; read -r SNOW_URL
printf 'ServiceNow user: '; read -r SNOW_USER
printf 'ServiceNow password: '; read -rs SNOW_PASSWORD; echo
```

Then run:

```sh
kargo create generic-credentials --project guestbook kargo-step-snow \
  --set instanceURL="$SNOW_URL" --set username="$SNOW_USER" --set password="$SNOW_PASSWORD"
unset SNOW_URL SNOW_USER SNOW_PASSWORD
```

<details>
<summary>What it does</summary>

Each `printf` shows a label, and `read` waits for what you paste. The `kargo` command sends the three values to Kargo, which stores them in a
Secret called `kargo-step-snow`. `unset` forgets them in your terminal. They never sit in a file.

The address has no `/` at the end, for example `https://dev123456.service-now.com`. The user is a shared workshop user: it can open and
update change requests, nothing more. The instructor disables it at the end of the session.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the Secret was created, and `kargo get generic-credentials --project guestbook` lists `kargo-step-snow`.
</details>

## 2. Make prod wait for a change request

Copy the starting file to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-12 work/
```

Open `work/lab-12/stage-prod.yaml`. It is your `prod` Stage of Lab 9, but the approval is replaced by three ServiceNow steps, and a fourth
one closes the change at the end. Replace the three `TODO`s, then apply it:

```sh
kargo apply -f work/lab-12/stage-prod.yaml
```

<details>
<summary>What it does</summary>

The promotion of `prod` now does this:

1. `get-user-input` asks for a reason, as in Lab 9.
2. `snow-create` opens a change request in ServiceNow. Your reason is its description. The change is *normal*, so it needs approval.
3. `snow-wait-for-condition` asks ServiceNow every 15 seconds for the state of that change request. The promotion stays **Running** until the
   change is in *Implement*.
4. The usual steps change the three regions in Git.
5. `snow-update` moves the change request to *Review* and adds a note. The work is done.
6. `record-audit-event` writes down the release, the reason and the number of the change.

`snow-create` gives its step a name (`as: snow-create`) and a result: the number and the `sys_id` of the new record. The other ServiceNow
steps use the `sys_id` to find the same change request. All three steps share the same credentials, written once with `&snowCredentials`
and used again with `*snowCredentials`.
</details>

<details>
<summary>Hint</summary>

- The Secret has a `username` and a `password`. The two types of credentials are `basic` and `api-token`.
- What `snow-create` produced is read as `outputs['snow-create']`. The field you need is `sys_id`. Inside `${{ }}`.
- A condition is written `field=value`. The state is called `state`.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the Stage `prod` was configured.
</details>

## 3. Promote to production

Run:

```sh
kargo promote --project guestbook --stage prod --warehouse app
```

Open the Kargo UI, find the Promotion of `prod`, answer the form with a reason, as in Lab 9, and submit it.

<details>
<summary>What you should see</summary>

The Promotion is **Running**. The step `snow-create` succeeds in a few seconds. Open its output: it has the number of your change request, for
example `CHG0030035`, and a link to it in ServiceNow. The link opens ServiceNow and asks for a login. You do not need it: the instructor shows the
list of changes on the screen.

The next step, `snow-wait`, keeps running. It is waiting for the approval.

![](/assets/lab-12-snow-wait.png)
![](/assets/lab-12-snow-cr.png)
</details>

## 4. Wait for the approval

In a company, the Change Advisory Board looks at the change and approves it. In the workshop, the instructor plays the board: once everybody has
opened a change request, they approve all of them at once, with a script in ServiceNow. Wait for it.

<details>
<summary>What you should see</summary>

A few seconds after the approval, the step `snow-wait` succeeds. Its message says that the record meets the condition `state=-1`. The
promotion goes on: the three regions change in Git, and `snow-update` closes the change request.
</details>

## 5. See the result

Run:

```sh
kargo get promotions --project guestbook --stage prod
```

<details>
<summary>What you should see</summary>

The Promotion is **Succeeded**. In the Kargo UI, the output of `snow-update` says `updated successfully in table change_request`, and the three
regions, `prod-amer-east`, `prod-amer-west` and `prod-emea`, promote by themselves as in Lab 3. In ServiceNow your change request is in
*Review*, with the note that Kargo wrote.
</details>

<details>
<summary>What just happened</summary>

Kargo did not know ServiceNow's approval rules, and ServiceNow did not know Kargo. The promotion opened a ticket, waited for a state, and went
on. The people who approve changes did not have to learn a new tool, and the change leaves a trace on both sides: the change request in
ServiceNow, and the audit event in Kargo.
</details>

## 6. Check your work

Run:

```sh
make check STEP=12
```

<details>
<summary>What it does</summary>

Checks that the Secret exists, that `prod` has the three ServiceNow steps and waits for `state=-1`, and that a promotion of `prod` opened a change
request and closed it. It also tells you if a `TODO` is left.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 12 for you, and you can read the finished file in `steps/12/`. It skips the labs that are
already done. It needs the Secret of step 1 (and the one of Lab 11): a script cannot invent the user and the password. It also waits for the
approval of the instructor, for up to 15 minutes.

```sh
make catchup STEP=12
```

## Stuck?

- **`make catchup` says there is no Secret called `kargo-step-snow`:** do step 1.
- **The step `snow-create` fails with an error about the login:** the user or the password is wrong. Create the Secret again:
  `kargo delete generic-credentials --project guestbook kargo-step-snow`, then step 1.
- **The step `snow-create` fails because it cannot reach ServiceNow:** the address is wrong. It must start with `https://` and have no `/` at the end.
- **The Promotion stays on `snow-wait`:** it is waiting for the approval. This is expected. Tell the instructor if everybody else has gone on.
- **The change request is in Implement, but the Promotion stays on `snow-wait`:** open the step. Its message says which condition it waits for,
  for example `does not yet meet condition: state=1`. The condition must be `state=-1`, with the minus sign. Fix your file and apply it.
  A Promotion keeps the steps it started with, so abort the stuck one: `kargo promote --project guestbook --name <name of the Promotion> --abort`.
  Then promote again, answer the form, and ask the instructor to approve the new change request.
- **Kargo asks for a reason again:** every promotion of `prod` asks. Answer the form.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses the file:** compare it with the example above. Indentation matters in YAML.

<details>
<summary>For the instructor: approving all the changes at once</summary>

A *normal* change needs six approvals from the Change Advisory Board. With a hundred attendees, that is too many to click, so one script
approves them all. It is in `workshop/lab-12/instructor/approve-workshop-changes.js`.

Create it once, before the workshop. In ServiceNow, as an administrator:

1. Open **All → System Definition → Fix Scripts**, and press **New**.
2. Name: `Kargo workshop - approve changes`. Leave **Run once** unchecked. Paste the script in **Script**, and submit.
3. Save a second Fix Script with `DRY_RUN = true` if you want to see what the script would do before it does it.

Run it when the attendees have promoted `prod`: open the Fix Script and press **Run Fix Script**. It approves all the pending approvals of the
changes that:

- were created by the workshop user (`CREATED_BY`, `kargo-workshop` in the script),
- have a short description that starts with `Kargo workshop` (do not change that text in the Stage), and
- are waiting for approval (*Authorize*) or are scheduled.

The approvals move a change to *Implement* by themselves, and Kargo notices within 15 seconds. Run the script again for the attendees who are late:
it only touches the changes that are still waiting. The output of the script lists every change and how many approvals it approved.

The changes stay in ServiceNow after the workshop. The workshop user needs the roles `itil` and `sn_change_write`, and **Web service access
only** checked. Disable it, or change its password, when the session ends.
</details>
