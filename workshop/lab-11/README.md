# Lab 11 - Beyond Kubernetes

**Goal:** promote more than Kubernetes. The promotion of `dev` will apply a Terraform that makes a small backend on AWS, a Lambda, and give
the address of that backend to the application. One piece of Freight moves both. It takes about 20 minutes.

This lab uses **Kargo Enterprise** features. The Terraform steps are marked **Beta** in the docs.

Before you start, finish Lab 10: the Promotion Controller must be on. `make check STEP=10` should say `All good.` If it does not, run
`make catchup STEP=10`. In a new terminal, run `export PATH="$PWD/.tools/bin:$PATH"` first. Your `kargo` login is remembered.

## The words of this lab

- **Terraform** (here **OpenTofu**, its open-source twin) describes infrastructure in files, and `apply` makes the real world match them.
- A **Lambda** is a function that AWS runs for you. A **Function URL** gives it a public web address.
- The **state** is the memory of Terraform: what it already made. It lives in a bucket on AWS, in a file that belongs to you only. That is why
  applying twice does not make a second Lambda.
- **Tags** are labels on what is created in AWS: who owns it, what it is for. Everything you create here has them.

Know more: [`hcl-update`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/hcl-update),
[`tf-apply`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/tf-apply) and
[`tf-output`](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/tf-output).

## 1. Give Kargo the AWS credentials

The instructor gives you an AWS access key and its secret. Kargo keeps them in a Secret and uses them only when a promotion applies the
Terraform. Run these three lines, one after the other. After the first two, paste the value and press Enter: nothing appears on the screen.

```sh
read -rs AWS_ACCESS_KEY_ID; read -rs AWS_SECRET_ACCESS_KEY
kargo create generic-credentials --project guestbook aws-creds \
  --set AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" --set AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
```

<details>
<summary>What it does</summary>

`read -rs` waits for what you paste and does not show it. The second command sends the two values to Kargo, which stores them in a Secret
called `aws-creds`. The third forgets them in your terminal. They never sit in a file.

Kargo shows the value of a Secret as `*** REDACTED ***`, so you cannot read it back. These are shared workshop credentials: they can only
manage Lambdas of this workshop, and the instructor disables them at the end of the session.
</details>

<details>
<summary>What you should see</summary>

Kargo confirms that the Secret was created, and `kargo get generic-credentials --project guestbook` lists `aws-creds`.
</details>

## 2. Look at the Terraform

The Terraform is in your GitOps repository, next to the values of each environment. Open
`http://gitea.localtest.me/workshop/guestbook-gitops/src/branch/main/env/dev/terraform` and read `main.tf`, `provider.tf` and `env.auto.tfvars`.

<details>
<summary>What you should see</summary>

- `main.tf` makes a Lambda called `kargo-guestbook-<your id>-dev`, a public Function URL for it, and the permissions to call it. The code of
  the Lambda is the folder `lambda/` of the same repository.
- `provider.tf` says where the state is kept (a bucket on AWS, in a folder with **your id**) and which tags everything gets: `owner`,
  `cost_center`, `purpose` and `participant`.
- `env.auto.tfvars` has your id, the name of the environment and `image_tag`: the version that runs. A promotion will change it.

Your id is your prefix plus four characters, so that two people with the same prefix do not share a Lambda.
</details>

## 3. Add the Terraform to dev

Copy the starting file to your work folder:

```sh
mkdir -p work && cp -R workshop/lab-11 work/
```

Open `work/lab-11/stage-dev.yaml`. It is your `dev` Stage with five new steps: two tell the Terraform what to do, one applies it, one reads its
result, and one gives the address of the Lambda to the application. Replace the three `TODO`s, apply it, and promote:

```sh
kargo apply -f work/lab-11/stage-dev.yaml
kargo promote --project guestbook --stage dev --warehouse app
kargo get promotions --project guestbook --stage dev
```

Run the last command again every few seconds. The first time takes about a minute and a half.

<details>
<summary>What it does</summary>

The promotion of `dev` now does this, after cloning the repository:

1. `yaml-update` writes the new image tag in the values of the application, as before.
2. `hcl-update` writes the same tag in the variables of the Terraform. The Lambda reports it as its version.
3. `tf-apply` applies the Terraform. The credentials come from the Secret, with `secret()`.
4. `tf-output` reads what the Terraform made: the `lambda_url` output.
5. `yaml-update` writes that URL in the values of the application, in `env.LAMBDA_URL`.

Then the usual steps commit, push and ask Argo CD to sync. The application reads the URL when it starts and calls the Lambda.
</details>

<details>
<summary>Hint</summary>

- The variable of the Terraform that holds the image tag is in `env.auto.tfvars`. The promotion should write the version in it.
- The Secret has two keys: the first one is used in the line above the one you are asked to write.
- The step that reads the Terraform result is called `tf-output`. Its output `lambda_url` has a `value`, so it is written
  `outputs['tf-output'].lambda_url.value`, inside `${{ }}`.
</details>

<details>
<summary>What you should see</summary>

The Promotion is **Running** for about a minute and a half, then **Succeeded**. In the Kargo UI, open the step `tf-apply`: its output is the
whole Terraform plan and ends with `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` The step `tf-output` has the address of the
Lambda.

![](/assets/lab-11-promote-dev.png)

</details>

## 4. See the result

To find the address of the Lambda, read it from the Git repository:

```sh
curl -s http://gitea.localtest.me/workshop/guestbook-gitops/raw/branch/main/env/dev/k8s/values.yaml
```

You can also see the address of the Lambda in the output of the `tf-output` step, in the Kargo UI:

![](/assets/lab-11-tf-output.png)

Then open the address in your browser, and open `http://guestbook-dev.localtest.me`.

<details>
<summary>What you should see</summary>

The values file has a line `LAMBDA_URL:` with a web address that ends with `.lambda-url.us-east-1.on.aws/`. If you open that address, the Lambda
answers a small piece of JSON with the stage and the version:

```
{"stage": "dev", "version": "1.4.0", "message": "Hello from the guestbook backend ..."}
```

![](/assets/lab-11-lambda-answer.png)

The page of `dev` has a new line, `Backend:`, with that address and the answer of the Lambda.

![](/assets/lab-11-result-app.png)

</details>

<details>
<summary>What just happened</summary>

One piece of Freight moved two things: the image of the application in Kubernetes, and the version of a function on AWS. Kargo did not
know AWS: it ran Terraform, as one more step. You can do the same with anything that has a tool and a command.
</details>

## 5. Promote again

Run the promotion once more:

```sh
kargo promote --project guestbook --stage dev --warehouse app
```

<details>
<summary>What you should see</summary>

The Promotion succeeds again, and the output of `tf-apply` says `No changes. Your infrastructure matches the configuration.` and
`Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` The state remembered the Lambda, so nothing was made twice. This is why you can
repeat a promotion, or run `make catchup`, without filling AWS with copies.

![](/assets/lab-11-tf-apply.png)

</details>

## 6. Extra: staging and prod

This is optional. The same idea, for the other two environments. In the folder `work/lab-11/extra` there are your `staging` and `prod` Stages, already
written: they keep the pull request of Lab 5 and the approval of Lab 9, and add the Terraform steps. Apply them and promote, one after the other:

```sh
kargo apply -f work/lab-11/extra/stage-staging.yaml
kargo apply -f work/lab-11/extra/stage-prod.yaml
kargo promote --project guestbook --stage staging --warehouse app
```

Merge the pull request in Gitea, as in Lab 5, and wait for the Promotion to succeed. Then promote `prod`, and answer the form and approve in the Kargo
UI, as in Lab 9:

```sh
kargo promote --project guestbook --stage prod --warehouse app
```

<details>
<summary>What it does</summary>

Each Stage has its own Terraform, in its own folder, and its own state file. So `staging` makes a second Lambda and `prod` a third.

- In `staging`, the Terraform is applied **before** the pull request is opened: the Lambda is updated first, and the pull request carries the change of Git.
- In `prod`, the Terraform is applied **after** the approval. There is one Lambda for the three regions: its address is written in the values of
  `prod-amer-east`, `prod-amer-west` and `prod-emea`.
</details>

<details>
<summary>What you should see</summary>

The output of `tf-apply` of each Promotion ends with `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` The values file of `staging`, and the
three of the regions, have a `LAMBDA_URL` with a web address that ends with `.lambda-url.us-east-1.on.aws/`. Each one is different: `dev`, `staging` and
`prod` have a Lambda each.

In AWS you now have three functions with your id: `kargo-guestbook-<your id>-dev`, `-staging` and `-prod`, all with the same tags.
</details>

## 7. Check your work

Run:

```sh
make check STEP=11
```

<details>
<summary>What it does</summary>

Checks that the Secret exists, that `dev` has the three Terraform steps, that a promotion applied the Terraform, that the values of `dev` have
the address of the Lambda, that the Lambda answers, and that the application knows the address. It also tells you if a `TODO` is left.
</details>

<details>
<summary>What you should see</summary>

Every line starts with `ok`, and the last line says `All good.` A line starting with `FAIL` says what to do.
</details>

## Behind? Catch up

If you are stuck or late, this does Labs 1 to 11 for you, and you can read the finished file in `steps/11/`. It needs the Secret of step 1:
a script cannot invent the key.

```sh
make catchup STEP=11
```

## Stuck?

- **`make catchup` says there is no Secret called `aws-creds`:** do step 1.
- **The step `tf-apply` fails with `AccessDenied` or `InvalidClientTokenId`:** the credentials are wrong or no longer valid. Create the Secret
  again: `kargo delete generic-credentials --project guestbook aws-creds`, then step 1.
- **The step `tf-apply` fails and mentions a name that already exists:** a function with that name exists without a state. Tell the instructor.
- **The step that writes `env.LAMBDA_URL` fails with `key path not found`:** the values file of `dev` has no `LAMBDA_URL`. Run `make seed`.
- **The Promotion takes more than three minutes:** `tf-apply` downloads the AWS provider each time. Give it a little more, then tell the instructor.
- **`make check` says a `TODO` is left:** it tells you the line.
- **Kargo refuses the file:** compare it with the example above. Indentation matters in YAML.
