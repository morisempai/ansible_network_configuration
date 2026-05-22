# backup_config

Pulls the running configuration from **every network device** and writes it to
a timestamped file in a git-tracked backup tree. Runs **first** in `site.yml`
so there is always a known-good config to roll back to before any change is
applied — see "Backup before change (always)" in `docs/testing.md`.

This is an **output role**: it reads device state and writes files on the
control node. It never changes a device, so it is safe to run unattended and
behaves identically under `--check`.

## Variables

The role consumes three variables. `tasks/assert.yml` validates them before
any device is touched.

| Variable                  | Type | Required | Purpose                                                                 |
|---------------------------|------|----------|-------------------------------------------------------------------------|
| `backup_config_dir`       | str  | yes      | Directory on the control node for the backup tree. Defaults relative to the playbook. |
| `backup_config_timestamp` | str  | yes      | Timestamp stamped into every filename. Resolved once per run.           |
| `backup_config_git_push`  | bool | yes      | When true, commit + push `backup_config_dir` to its git repo after backup. Default `false`. |

```yaml
backup_config_dir: /srv/network-backups
backup_config_git_push: true
```

## Supported device classes

| `ansible_network_os` | Behaviour                                                                       |
|----------------------|---------------------------------------------------------------------------------|
| `cisco.ios.ios`      | `ios_command` runs `show running-config`; written as `.cfg`                     |
| `cisco.nxos.nxos`    | `nxos_command` runs `show running-config` on the MDS 9132T SAN switch; `.cfg`    |
| `nokia.srlinux`      | `nokia.srlinux.get` reads the running datastore; written as `.json`             |
| `frr.frr`            | `cli_command` runs `show running-config`; written as `.cfg`                     |
| `fortinet.fortios`   | `fortios_monitor_fact` (`system_config_backup` selector); written as `.conf`    |

Every device class has a real implementation — there is **no no-op stub**.
Unlike `vlans`/`interfaces`, the Cisco MDS 9132T is *not* exempt: it is a
Fibre Channel SAN switch but it still runs NX-OS and still has a device
configuration that must be captured before any change (see
`docs/architecture-brief.md`). `tasks/cisco_nxos.yml` backs it up like any
other device.

There is no `linux.yml`: a plain Linux server has no network "running-config",
so on a non-network host the dispatcher matches nothing and the role resolves
to a clean no-op after creating the backup directory.

The FortiGate VDOM (`fortios_vdom`, default `root`) can be overridden per
host/group.

## NetBox source of truth

`backup_config` has no device data to model in NetBox, but its *behaviour* can
be centrally overridden from a device's **config context** (see
`docs/netbox.md`):

| Config-context key         | Overrides                |
|----------------------------|--------------------------|
| `backup_config_dir`        | `backup_config_dir`      |
| `backup_config_git_push`   | `backup_config_git_push` |

When `netbox_enabled` is off (lab, Molecule) `tasks/netbox.yml` never runs and
the `defaults/` values stand. `backup_config_timestamp` is run metadata, not
device data, and is never sourced from NetBox.

## Example

```yaml
- hosts: network
  gather_facts: false
  roles:
    - role: backup_config        # always first — rollback insurance
```

This is exactly what `ansible/playbooks/backup.yml` does; `site.yml` imports
it ahead of every other playbook.

## Output layout

One file per device, grouped by hostname, all sharing one run timestamp:

```
{{ backup_config_dir }}/
  <hostname>/
    <hostname>-YYYYmmdd-HHMMSS.cfg     # Cisco IOS, NX-OS, FRR
    <hostname>-YYYYmmdd-HHMMSS.json    # Nokia SR Linux
    <hostname>-YYYYmmdd-HHMMSS.conf    # FortiGate
```

## Git publishing

When `backup_config_git_push` is true, `tasks/git.yml` runs once on the
control node after every device has written its file: it `git add -A`s the
backup tree, commits with the run timestamp, and pushes. The commit/push
steps run only when something was actually staged, so an unchanged run is a
genuine no-op.

`backup_config_dir` **must already be a git work tree with a configured
remote** — the role does not clone or `git init` it. In production that
checkout is provisioned out-of-band by AWX or the bootstrap. The git steps
use `ansible.builtin.command` (not `ansible.builtin.git`, which manages
checkouts rather than commits) with explicit `changed_when` / `failed_when`.

## `--check` mode

Backup is a read operation, so the role is `--check`-safe by design:

- Every device fetch is a read-only `show`/`get`/`GET` and is marked
  `check_mode: false` so the backup still happens during a dry run.
- The backup-directory creation is marked `check_mode: false` so the read
  tasks have a destination.
- In `--check` the read tasks write nothing, so the git working tree stays
  clean and the commit step is correctly skipped.

## Scope and known limitations

- **Network devices only.** Linux and Windows server configs are out of
  scope; there is no `linux.yml` / `windows.yml`.
- **No retention/rotation.** The role only ever adds files. Pruning old
  backups (by age or count) is left to the backup repository's own policy.
- **Git repo must pre-exist.** `tasks/git.yml` commits and pushes but never
  creates or clones `backup_config_dir`; provisioning that checkout and its
  remote/credentials is an environment concern.
- **FortiGate path is verified by construction, not CI.** The Cisco /
  FortiGate / SR Linux device paths are not exercised by Molecule (Linux
  only) — see the per-class table in `docs/testing.md`. The
  `fortios_monitor_fact` `system_config_backup` selector returns the raw
  configuration under `meta.raw`; the FortiGate task asserts that payload is
  non-empty rather than silently writing a zero-byte rollback artefact.
