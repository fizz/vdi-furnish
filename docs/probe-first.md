# Probe the box before you write the playbook

Never debug a furnish playbook by running the playbook. Do the steps by hand over SSM
until the machine is in the state you want, then write the playbook to reproduce what
already worked.

A playbook is a poor debugger for four reasons:

- **One defect per run.** A furnish is serial, so it surfaces one problem at a time and
  each discovery costs a full run. One build took thirteen rounds for thirteen defects,
  and every one was answerable in advance by asking the machine.
- **The failure comes late.** Docker Desktop installs for minutes before git gets a
  chance to fail.
- **Every fix drags a change-control tail** if the playbook is under review: a commit, a
  PR, approvals, a merge, a plan and an apply.
- **The playbook's job is reproducibility, not discovery.**

## One preflight command

Ask every precondition at once, in one round trip:

- Which packages the image already ships. `Get-Command aws, git, docker, tailscale`
  on Windows, `command -v` on Linux.
- Whether a reboot is pending: `PendingFileRenameOperations`, and the Component Based
  Servicing `RebootPending` key.
- Whether each network destination answers: `Test-NetConnection <host> -Port <p>`.
  A security-group rule that applied is not a path that works.
- Whether the payload itself is on the machine. A furnish that installs a runtime and
  not the thing it runs has not furnished anything.
