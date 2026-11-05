# vdi-furnish

Ansible that takes a bare EC2 desktop or workspace to a working one over AWS Systems
Manager. No inbound SSH, no WinRM port, no key distribution. Two siblings:

| Directory | Builds | Reaches it with |
| --- | --- | --- |
| `windows/` | A Windows Server desktop with Docker Desktop (WSL2 backend), NICE DCV, Tailscale or Headscale, and an idle stop | `community.aws.aws_ssm`, PowerShell |
| `linux/` | A developer workspace, **Amazon Linux 2023 or Ubuntu 24.04**, with Docker, a data volume, named accounts keyed from GitHub, the same tailnet join, and an idle stop | `community.aws.aws_ssm`, sh |

`linux/furnish.yml` reads `/etc/os-release` and loads `vars/<os>.yml` and `tasks/<os>.yml`
for what differs: package names, Docker's Compose and Buildx plugins, the Tailscale
repository, the SSH unit and the login group. Force one with `-e linux_os=al2023` or
`-e linux_os=ubuntu`. Any other OS stops the run before anything is installed.

Both are idempotent and safe to re-run. Everything account-, region-, domain- and
person-specific is a variable.

## Status

The patterns were proven by hand on live machines. The playbooks in this repo are a
rewrite from those patterns and have not been run end to end yet. Run one against a
throwaway instance before trusting it, and read [docs/probe-first.md](docs/probe-first.md)
before you debug it.

## What to take if you take nothing else

- **The idle stop gates on the work, not on a timer.** A batch can run for tens of minutes
  with nobody connected. A timer kills it mid-flight. See `windows/files/idle-stop.ps1`
  and the `busy_check_cmd` variable in `linux/furnish.yml`.
- **Unknown is busy.** If the script cannot ask the engine whether a run is in flight, it
  does not stop the machine.
- **The traps** in [docs/traps.md](docs/traps.md), each paid for once.

## Use

```bash
ansible-galaxy collection install -r windows/requirements.yml -p ./.collections
export AWS_PROFILE=<profile> AWS_REGION=<region> AWS_DEFAULT_REGION=<region>
# macOS control node, or every run dies with "worker found in a dead state":
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*'
ansible-playbook -i windows/inventory.aws_ec2.yml windows/furnish.yml
```

A macOS control node can print "worker found in a dead state" and still exit 0, with no
`PLAY RECAP`. Check for the recap, not the exit code.

## Licence

MIT. See [LICENSE](LICENSE).

## Not included

The instance, its network and its IAM role. Build those with whatever you build instances
with. A desktop module that does it for Windows is
[terraform-aws-dcv-vdi](https://github.com/fizz/terraform-aws-dcv-vdi).
