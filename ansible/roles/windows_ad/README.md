# windows_ad

Promotes Windows Servers to **Active Directory Domain Services** domain
controllers. HQ hosts the primary DC (the forest root); R1 and R2 host
replica DCs so authentication survives a WAN outage
(`docs/architecture-brief.md`).

This role declares *that a host is a domain controller*. It does not manage
domain objects (users, groups, OUs, GPOs) or DNS zone content - those belong
to follow-on roles.

## Supported device classes

Windows only. Unlike the network roles, `windows_ad` does **not** dispatch
per vendor: `tasks/main.yml` includes `tasks/windows.yml` directly. The
`windows.yml` file name is kept for parity with the dispatcher convention
(see `docs/adding-a-role.md`).

| Connection | Notes                                                        |
|------------|--------------------------------------------------------------|
| `winrm`    | Windows Server 2012+; the host must already be WinRM-reachable on the management VLAN. Initial network / WinRM bootstrap is out of scope - see `playbooks/bootstrap.yml`. |

## What it does

- Installs the `AD-Domain-Services` Windows feature (with management tools).
- Promotes the host to a domain controller:
  - **primary** (`windows_ad_is_primary: true`) - creates a new forest
    rooted at `windows_ad_domain` (`microsoft.ad.domain`);
  - **replica** (`windows_ad_is_primary: false`) - joins the existing
    domain and replicates from `windows_ad_replica_of`
    (`microsoft.ad.domain_controller`).
- Reboots the host when the promotion requires it (`reboot: true`).

Both `microsoft.ad` modules are idempotent: once a host is a domain
controller a second run reports `changed=0`.

## Variables

| Variable                        | Type | Required          | Purpose                                                    |
|---------------------------------|------|-------------------|------------------------------------------------------------|
| `windows_ad_domain`             | str  | yes               | AD domain FQDN (dotted), e.g. `corp.example.internal`      |
| `windows_ad_is_primary`         | bool | yes               | `true` promotes the primary DC (new forest); `false` a replica |
| `windows_ad_replica_of`         | str  | replica only      | FQDN of an existing DC to replicate from                   |
| `windows_ad_safe_mode_password` | str  | yes               | DSRM (Directory Services Restore Mode) password - **vault** |
| `windows_ad_join_user`          | str  | replica only      | Domain-admin account authorising the replica promotion - **vault** |
| `windows_ad_join_password`      | str  | replica only      | Password for `windows_ad_join_user` - **vault**            |

`windows_ad_domain`, `windows_ad_is_primary` and `windows_ad_replica_of` are
defined in `group_vars/windows.yml` (or NetBox - see below).

### Vault-sourced secrets

`windows_ad_safe_mode_password`, `windows_ad_join_user` and
`windows_ad_join_password` are credentials. They have **no defaults** in
`defaults/main.yml` (deliberately) and are **never** sourced from NetBox.
Supply them from Ansible Vault - `group_vars/windows.yml` maps the `vault_*`
variables onto the role variables:

```yaml
# group_vars/windows.yml
windows_ad_safe_mode_password: "{{ vault_ad_safe_mode_password }}"
windows_ad_join_user: "{{ vault_ad_join_user }}"          # e.g. CORP\\svc-adjoin
windows_ad_join_password: "{{ vault_ad_join_password }}"
```

The join credentials are required only for a **replica** promotion (which
must authenticate to the live domain). The primary creates a new forest and
needs neither. Every task that consumes a secret sets `no_log: true`.

## NetBox source

When `netbox_enabled` is true, `tasks/netbox.yml` resolves the non-secret
inputs from the device's **config context** (`windows_ad` has no native
NetBox object). It reads `windows_ad_domain`, `windows_ad_is_primary` and
`windows_ad_replica_of`, falling back to the `defaults/` value for any key
the config context omits. The vault-sourced secrets above are **never**
read from NetBox. See `docs/netbox.md`.

## Input validation

`tasks/assert.yml` checks the inputs before the host is promoted:

- `windows_ad_domain` is a non-empty dotted (FQDN) domain name.
- `windows_ad_is_primary` is a boolean; a replica (`false`) must set
  `windows_ad_replica_of`.
- `windows_ad_safe_mode_password` is provided (no default - from vault).
- `windows_ad_join_user` and `windows_ad_join_password` are provided when
  the host is a replica.

The boolean checks coerce with `| bool`: a value resolved through a
templated `config_context` default comes back as the string `"true"` /
`"false"` rather than a native boolean
(see `memory/ansible_templating_gotcha.md`).

## Example

```yaml
- hosts: windows
  roles:
    - role: windows_ad
```

```yaml
# host_vars/hq-dc01.yml  - the forest root
windows_ad_is_primary: true

# host_vars/r1-dc01.yml  - a replica
windows_ad_is_primary: false
windows_ad_replica_of: hq-dc01.corp.example.internal
```

## Known limitations

- **CI is lint-only for this role.** A Windows DC cannot be promoted in a
  Linux container, so the Molecule scenario uses the `delegated` driver and
  is excluded from the PR Molecule matrix. CI runs `ansible-lint` and a
  syntax check only. A real `converge` / `verify` run needs a Windows test
  host (a `windows-latest` GitHub runner, or a local Windows VM) reachable
  via the `MOLECULE_WINDOWS_HOST` environment variable, and is exercised in
  staging against a Windows Server VM (`docs/testing.md`).
- **Bootstrap is out of scope.** The host must already be WinRM-reachable.
  Initial IP / WinRM setup belongs to `playbooks/bootstrap.yml`.
- **Promotion only.** Domain objects (users, groups, OUs, GPOs) and DNS
  zone content are not managed here.
- **Forest/domain functional levels** default to the values
  `microsoft.ad` computes for the target OS; this role does not pin them.
