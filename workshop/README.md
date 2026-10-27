# Kargo workshop guides

Follow the guides in order. Each one is a short list of steps.

| Guide | When | What |
|---|---|---|
| [00 - Before the workshop](00-before-the-workshop.md) | a few days before | Get the project, prepare your laptop |
| [01 - Your environment](01-your-environment.md) | at the start of the workshop | Create your cluster and connect it to the Akuity Platform |
| [Lab 1 - Your first promotion](lab-1/README.md) | after the setup | Send the first release to `dev` |
| [Lab 2 - Build the pipeline](lab-2/README.md) | after Lab 1 | Add `staging`, let `dev` promote by itself |
| [Lab 3 - Production in three regions](lab-3/README.md) | after Lab 2 | Add the `prod` gate and three regions that follow it |

The other labs follow.

## How to read a step

Every step starts with **what to do**. Two folded boxes follow:

- **What it does** explains the command.
- **What you should see** tells you how to know it worked.

Try the step first, then open the boxes.

## If something goes wrong

Run `make doctor`. It checks your laptop and tells you what to fix. If you are still stuck, ask for help in the room.
