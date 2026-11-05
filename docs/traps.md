# Traps

Each one cost an afternoon at least once.

## Over SSM

- **A long command reports Failed after it succeeded.** Run Command executes inside
  `ssm-document-worker`, which holds an IPC channel open for the whole invocation, so a
  long install (a large MSI, a big `choco`) blows the IPC timeout. The command is fine;
  the invocation is not. Write the command to a script, register and start a one-shot
  scheduled task, let the SSM call return, and poll for a sentinel file.
- **Getting files out is capped at 24 KB.** `get-command-invocation` truncates stdout.
  Generate S3 presigned PUT URLs locally, embed them in the command, and have the
  instance PUT each file.
- **The Ansible `aws_ssm` plugin needs a bucket** for every file it copies, and the
  instance role needs `s3:GetObject/PutObject/DeleteObject` on it. With a KMS bucket it
  also needs `kms:GenerateDataKey`, or the failure names S3 and never mentions the key.
  Do not use the Terraform state bucket for this.
- **Keep `ansible_aws_ssm_timeout` high** (3600). Without it a long install dies with
  "Broken pipe", and the message does not say the timeout is missing. If you hand-write
  a static inventory, copy every key the dynamic one composes.

## Windows

- **`win_reboot` succeeds and reports a timeout.** It cannot re-detect boot time through
  the SSM session the reboot just dropped. Tolerate the timeout, then poll until the
  machine accepts commands again.
- **Chocolatey treats "same version already installed" as MSI error 1603.** 1603 is the
  generic MSI error, so the text blames the environment. The Windows Server image already
  ships the AWS CLI. Probe with `Get-Command` and skip the install.
- **An Inno installer can exit 4 under SYSTEM over SSM and write no log anywhere.** A
  pending file rename causes it, but not always. `git.portable` is a zip extract with
  nothing to fail at.
- **Install packages one at a time.** One long `choco install a b c` drops mid-pipe.
- **A `netsh` portproxy will not bind unless the IP Helper service is running.** DCV
  refuses privileged ports, so a `443 -> 8443` portproxy is what gives a clean URL.
- **`wsl.exe` refuses to run as SYSTEM** (`WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`), so a
  SYSTEM scheduled task can never ask a container engine anything. Run the task as the
  login user.
- **Polling a WSL distro can start it.** `wsl -d <distro>` starts a stopped distro, and a
  five-minute poll then keeps the VM alive forever to be told it is idle. Check
  `wsl -l --running` first.
- **DCV does not read its certificate from the registry value.** Setting
  `certificate-file` does nothing. It reads `dcv.pem` and `private\dcv.key` under
  `C:\Windows\System32\config\systemprofile\AppData\Local\NICE\dcv\`. After a renewal,
  copy the full chain and key there and restart `dcvserver`.
- **win-acme's Route53 validation plugin ships as a separate zip.** Download it next to
  `wacs.exe`, or DNS-01 cannot validate.
- **The log your own script writes can be locked by a log shipper.** The CloudWatch
  agent tails a file and keeps a handle on it, and `Add-Content` then fails. Under
  `$ErrorActionPreference = 'Continue'` that is a silent skip with exit 0, so the gate
  keeps deciding and records nothing. Append with an explicit share mode and a retry.
- **Hibernation may not be possible.** A machine with nested virtualization on cannot
  hibernate. Do not ask the instance for it.

## Amazon Linux 2023

- **It packages Docker but not the Compose or Buildx plugins.** Install the upstream
  release binaries into `/usr/local/lib/docker/cli-plugins/`, pinned to a version at least
  two weeks old and verified against the checksum the release publishes. Ubuntu's
  `docker-compose-v2` and `docker-buildx` come signed from the archive, which is the one
  place Ubuntu is the stronger supply chain.
- **Do not name `curl` in a package list.** The image ships `curl-minimal`, and installing
  `curl` conflicts with it.
- **The SSM agent and the AWS CLI v2 are already there.** Probing for them and installing
  them is wasted tasks.
- **The SSH unit is `sshd`, not `ssh`, and the default login group is `ec2-user`.**
- **Use Tailscale's repository, not the install script.** The Amazon Linux 2023 repo checks
  both package and repository signatures.

## Certificates

- **On-box ACME needs no static key.** Put the instance role's own ARN in its trust
  policy. The ACME client then assumes the role it is already running under and gets
  fresh short-lived credentials for each DNS-01 challenge.

## Tailnet

- **Tailscale compares the login server as text.** A different spelling of the same URL
  fails with "can't change --login-server without --force-reauth".
- **Do not pass `--accept-routes` on a machine inside the advertised range.** It is a
  conflict, not a convenience.
- **Do not `no_log` the join.** It hides the real failure behind "censored". Scrub the
  key from the output instead, so the error stays readable and the secret never prints.
- **An old node holding the hostname makes the replacement register as `name-1`.**
  Delete the old node first.
- **With no inbound access at all, an unjoined machine is unreachable**, not degraded.
  Make the furnish fail hard on it.

## Idle stop

- **CPU is not the signal.** A measured desktop ran at 65% average CPU for three weeks
  with nobody connected.
- **The gate is the work.** A batch runs for tens of minutes with nobody watching.
- **Unknown is busy.** If the script cannot ask, do not stop.
- **A start needs a grace period**, or starting the machine stops it again before anyone
  finishes connecting.
- **Require consecutive idle samples**, so one failed poll does not stop a live session.
- **Waking is a separate problem.** A stopped instance has no listener. You need a small
  page, a Lambda function URL or a gateway to call `ec2:StartInstances`, scoped by tag.
