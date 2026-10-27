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

The other labs follow. The **Features** column says whether a lab uses open-source Kargo or Kargo Enterprise features.

## How to read a step

Every step starts with **what to do**. Two folded boxes follow:

- **What it does** explains the command.
- **What you should see** tells you how to know it worked.

Try the step first, then open the boxes.

Run `make check` right after its lab: a later lab changes things, and an earlier check may then report a difference.

## If something goes wrong

Run `make doctor`. It checks your laptop and tells you what to fix. If you are still stuck, ask for help in the room.
