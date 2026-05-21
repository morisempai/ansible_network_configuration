# windows_ad

Base configuration and Active Directory Domain Services for Windows Servers.
HQ hosts the primary domain controller; R1 and R2 host replicas for WAN
outage resilience.

## Supported device classes

Windows only.

## What it does

- Installs the AD-Domain-Services feature.
- Promotes the host to a domain controller (primary or replica, by group).
- Configures DNS forwarders.

## Variables

| Variable                       | Type | Purpose                                  |
|--------------------------------|------|------------------------------------------|
| `windows_ad_domain`            | str  | AD domain FQDN                           |
| `windows_ad_is_primary`        | bool | Promote as the primary DC, else a replica|
| `windows_ad_safe_mode_password`| str  | DSRM password (vault-encrypted)          |
| `windows_ad_replica_of`        | str  | Existing DC to replicate from (replica)  |

Defined in `group_vars/windows.yml`.

## Input validation

`tasks/assert.yml` checks the inputs before the host is promoted:

- `windows_ad_domain` is a dotted domain name.
- `windows_ad_is_primary` is a boolean; a replica (`false`) must set
  `windows_ad_replica_of`.
- `windows_ad_safe_mode_password` is provided — it has no default, so supply
  it from vault.

## Example

```yaml
- hosts: windows
  roles:
    - role: windows_ad
```

## Known limitations

This role assumes the host is already domain-reachable. Initial network and
WinRM bootstrap is out of scope — see `playbooks/bootstrap.yml`.
