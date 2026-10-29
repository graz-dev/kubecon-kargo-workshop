# Kargo workshop guides

Follow the guides in order. Each one is a short list of steps.

| Guide | When | What | Features |
|---|---|---|---|
| [00 - Before the workshop](00-before-the-workshop.md) | a few days before | Get the project, prepare your laptop | - |
| [01 - Your environment](01-your-environment.md) | at the start of the workshop | Create your cluster and connect it to the Akuity Platform | - |
| [Lab 1 - Your first promotion](lab-1/README.md) | after the setup | Send the first release to `dev` | Open source |
| [Lab 2 - Build the pipeline](lab-2/README.md) | after Lab 1 | Add `staging`, let `dev` promote by itself | Open source |
| [Lab 3 - Production in three regions](lab-3/README.md) | after Lab 2 | Add the `prod` gate and three regions that follow it | Open source |
| [Lab 4 - Verification and rollback](lab-4/README.md) | after Lab 3 | Check every release, catch a broken one, go back | Open source |
| [Lab 5 - A pull request as approval](lab-5/README.md) | after Lab 4 | `staging` waits until someone merges a pull request | Open source |
| [Lab 6 - Kargo finds the releases](lab-6/README.md) | after Lab 5 | The Warehouse follows the registry: a live release goes all the way to production | Open source |
| [Lab 7 - Notifications](lab-7/README.md) | after Lab 6 | Get a message when a promotion succeeds or fails | Enterprise |
| [Lab 8 - Automatic rollback](lab-8/README.md) | after Lab 7 | A broken release goes back by itself | Enterprise |
| [Lab 9 - Governance](lab-9/README.md) | after Lab 8 | A freeze, an approval and an audit trail for production | Enterprise |
| [Lab 10 - Custom steps](lab-10/README.md) | after Lab 9 | Run your own container as a step of a promotion (alpha) | Enterprise |
| [Lab 11 - Beyond Kubernetes](lab-11/README.md) | after Lab 10 | Apply Terraform from a promotion and give the Lambda it makes to the application | Enterprise |

The other labs follow. The **Features** column says whether a lab uses open-source Kargo or Kargo Enterprise features.

## How to read a step

Every step starts with **what to do**. Two folded boxes follow:

- **What it does** explains the command.
- **What you should see** tells you how to know it worked.

Try the step first, then open the boxes.

Run `make check` right after its lab: a later lab changes things, and an earlier check may then report a difference.

## If something goes wrong

Run `make doctor`. It checks your laptop and tells you what to fix. If you are still stuck, ask for help in the room.
