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

## Trusted DCV certificates on Linux

Linux DCV desktops can use the shared `vdi-furnish` certificate role instead of the
default self-signed certificate. Set `dcv_certificate_enabled: true` and provide the
hostname, contact email, Route 53 hosted-zone ID, and a narrowly scoped ACME role ARN.
The playbook uses Certbot's DNS-01 challenge, so the private desktop does not need to
be reachable from the public internet. The cross-account role should allow TXT changes
only for `_acme-challenge.<hostname>` and read access to the authoritative zone.

The task installs the certificate and private key at `/etc/dcv/dcv.pem` and
`/etc/dcv/dcv.key`, with DCV ownership and restrictive permissions. Certbot's renewal
timer uses the same short-lived instance-profile role and deploy hook. Keep the DNS
role and the hostname/zone configuration in the infrastructure repository; the
certificate installation and renewal behavior belongs here in this shared furnishing
repository. The current task supports Ubuntu 24.04 or newer.

Example variables:

```yaml
dcv_certificate_enabled: true
dcv_certificate_hostname: vdi.stage.example.com
dcv_certificate_email: ops@example.com
dcv_certificate_route53_zone_id: Z0123456789ABCDEFGHIJ
dcv_certificate_acme_role_arn: arn:aws:iam::123456789012:role/vdi-dns01-acme
dcv_certificate_aws_region: us-east-1
```

A macOS control node can print "worker found in a dead state" and still exit 0, with no
`PLAY RECAP`. Check for the recap, not the exit code.

## Licence

MIT. See [LICENSE](LICENSE).

## Not included

The instance, its network and its IAM role. Build those with whatever you build instances
with. A desktop module that does it for Windows is
[terraform-aws-dcv-vdi](https://github.com/fizz/terraform-aws-dcv-vdi).
