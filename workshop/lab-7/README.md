# Lab 7 - Notifications

**Goal:** know when a promotion finishes or fails, without watching a screen. You set up a place to send messages, tell Kargo which
events to send, and see a message arrive. It takes about 10 minutes.

This lab uses **Kargo Enterprise** features: notifications are part of Kargo on the Akuity Platform.

Before you start, finish Lab 6. `make check STEP=6` should say `All good.` If it does not, run `make catchup STEP=6`. In a new terminal, run
`export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- An **event** is something Kargo says it did: a promotion was created, succeeded, failed.
- A **MessageChannel** is a place where messages can go: a Slack channel, an email address, a web address. It holds the connection, not the
  message.
- An **EventRouter** chooses the events to follow and writes the message. It does not send anything itself: it hands the message to the
  channel.

Know more: [Notifications](https://docs.kargo.io/user-guide/reference-docs/events/notifications) and the
[events Kargo emits](https://docs.kargo.io/user-guide/reference-docs/events/event-reference).

## 1. Get an inbox

Messages need somewhere to arrive. For this lab it is a page on the web that keeps whatever is sent to it.

1. Open [webhook.site](https://webhook.site) in your browser.
2. It shows **Your unique URL**, which looks like `https://webhook.site/` followed by letters and digits. Copy it, and keep the page open.

<details>
<summary>What it does</summary>

The page is an inbox with an address. Anything sent to that address shows up on the page, with its content. Nobody needs an account, and
nothing is installed.

The address is public: anyone who knows it can read the inbox. The messages in this lab only say the name of a project, a Stage and a
promotion.
</details>

## 2. Set up the channel

Copy the starting files to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-7 work/
```

A channel always points to a Secret, even when the place it sends to needs no password. Ours does not, so we create a Secret with a
placeholder:

```sh
kargo create generic-credentials --project guestbook inbox-credentials --set bearerToken=workshop
```

Open `work/lab-7/message-channel.yaml`, replace the `TODO` with your address, and apply it:

```sh
kargo apply -f work/lab-7/message-channel.yaml
```

<details>
<summary>What it does</summary>

It creates a channel called `inbox` that sends web requests to your address. Kargo sends the placeholder as a token with each request. Your
inbox ignores it.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the Secret and the MessageChannel were created.

You can also see it in the Kargo UI, in the settings of the project, under **Notifications**:

![](/assets/lab-7-channel-config.png)

</details>

## 3. Choose the events

Open `work/lab-7/event-router.yaml`. Replace the two `TODO`s, then apply it:

```sh
kargo apply -f work/lab-7/event-router.yaml
```

<details>
<summary>What it does</summary>

The router follows three events: a promotion that succeeded, one that did not complete, and one that hit an unexpected error. For each
one it writes a small message with the event, the project, the Stage and the promotion, and gives it to the `inbox` channel.

The text between `${{` and `}}` is filled in by Kargo from the event, as in the promotions you wrote.
</details>

<details>
<summary>Hint</summary>

- The events of a promotion are `PromotionCreated`, `PromotionSucceeded`, `PromotionFailed`, `PromotionErrored`, `PromotionAborted` and
  `PromotionDiscarded`.
- The Stage a promotion went to is `event.stageName`.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms the EventRouter. If you made a mistake in the name of the channel, it says so: the router checks that the channel exists.

You can see it in the Kargo UI too:

![](/assets/lab-7-eventrouter-config.png)
</details>

## 4. Make things happen

First, a promotion that succeeds. Promote again what `dev` already runs:

```sh
kargo promote --project guestbook --stage dev --warehouse app
```

Look at your inbox in the browser.

<details>
<summary>What you should see</summary>

Within a few seconds a message arrives, with a body like this:

```
{"event":"PromotionSucceeded","project":"guestbook","promotion":"dev.<something>","stage":"dev"}
```

![](/assets/lab-7-notification-1.png)
</details>

Now one that fails. Promote an older version to `staging`, so that Kargo opens a pull request, and close the pull request without merging
it. Find the alias of 1.3.1 with `make freight`, and run:

```sh
make freight
kargo promote --project guestbook --freight-alias <alias of 1.3.1> --stage staging
```

Then open `http://gitea.localtest.me/workshop/guestbook-gitops/pulls`, open the pull request and click **Close pull request**.

<details>
<summary>What you should see</summary>

In a few seconds the Promotion fails, because nobody approved it. A second message arrives in the inbox:

```
{"event":"PromotionFailed","project":"guestbook","promotion":"staging.<something>","stage":"staging"}
```

![](/assets/lab-7-notification-2.png)

`staging` now shows an error. It has not changed: it still runs 1.4.0.

![](/assets/lab-7-staging-error.png)

Clear the error by promoting what it already has:

```sh
kargo promote --project guestbook --stage staging --warehouse app
```

</details>

<details>
<summary>What just happened</summary>

Two promotions, two messages, and you did not write a bot, a script or a webhook. Kargo emitted the events, the router wrote the
messages, and the channel sent them.
</details>

## 5. Extra: a real email with Gmail

This is optional. It is for when you want the messages in your mailbox, or to try at home. **You do not need it to finish the lab.**

Be careful with this one:

- You need a Gmail account with 2-step verification, and an **app password** for it. An app password can read the whole mailbox: use a
  personal account, never a work one, and delete the app password when you are done.
- It does not work with every account. Google does not offer app passwords for work, school or other organization accounts, for accounts
  with Advanced Protection, or when 2-step verification uses only security keys. If that is your case, skip this.

### Create the app password

1. Make sure 2-step verification is on in your Google Account (Security). If it is off, turn it on first.
2. Open [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) and sign in if asked.
3. Give the app password a name, for example `kargo-workshop`, and create it.
4. Google shows a password of 16 characters. **Copy it now**: it is shown only once. You can paste it with or without the spaces
   between the groups.

<details>
<summary>What it does</summary>

An app password lets one program send email as you, without knowing your real password. It works only for the name you gave it, and you
can remove it at any time.
</details>

When you are done with the lab, remove it: open the same page, find `kargo-workshop` in the list, and click **Remove**. From that moment
Kargo cannot send email as you any more.

### Put it in a Secret

The password goes into a Secret in Kargo, so it never sits in a file. Run these three lines in your terminal, one after the other:

```sh
read -rs APP_PASSWORD
kargo create generic-credentials --project guestbook smtp-credentials --set username=you@gmail.com --set password="$APP_PASSWORD"
unset APP_PASSWORD
```

<details>
<summary>What it does</summary>

1. `read -rs APP_PASSWORD` waits for you. **Paste the 16 characters and press Enter.** Nothing appears on the screen while you paste: that
   is on purpose, so nobody can read it over your shoulder.
2. The second line sends the Gmail address (replace `you@gmail.com` with yours) and the password to Kargo, which stores them in a Secret
   called `smtp-credentials`. The email channel will use it.
3. `unset APP_PASSWORD` forgets the password in your terminal.

You never type the password into a file, and it is not saved in your command history.
</details>

Then replace `you@gmail.com` with your own address in `work/lab-7/extra/message-channel-email.yaml` and
`work/lab-7/extra/event-router-with-email.yaml`, and apply them in this order:

```sh
kargo apply -f work/lab-7/extra/message-channel-email.yaml
kargo apply -f work/lab-7/extra/event-router-with-email.yaml
kargo promote --project guestbook --stage dev --warehouse app
```

<details>
<summary>What you should see</summary>

The inbox gets its message, and an email arrives in your mailbox with the same information. It can end up in the spam folder.

![](/assets/lab-7-email-sent.png)
</details>

## 6. Check your work

Run:

```sh
make check STEP=7
```

<details>
<summary>What it does</summary>

Reads your inbox and checks that it received a message for a promotion that succeeded and one for a promotion that failed. It also checks
that the credentials exist, and tells you if a `TODO` is left in your files. It does not look at the email extra.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 7 for you, and you can read the finished files in `steps/7/`. It makes its own inbox and
prints its address: open it to see the messages.

```sh
make catchup STEP=7
```

## Stuck?

- **Kargo says the channel needs a `secretRef`:** create the credentials first, with the `kargo create generic-credentials` command above.
- **Kargo says the channel was not found when you apply the router:** apply the channel first. If you did, wait ten seconds, because the platform takes a moment to see it, and apply the router again.
- **Nothing arrives in the inbox:** check that the address in your file is the one on the page, and that the router has an `output`.
  Then promote again.
- **The pull request is merged, not closed:** the promotion succeeds, and you get a second success message. Try again with an older version.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses a file:** compare it with the example above. Indentation matters in YAML.
