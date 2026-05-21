# users_aaa

Local user accounts and AAA: RADIUS/TACACS+ servers, and the 802.1X RADIUS
client configuration that backs wired NAC.

## Supported device classes

Cisco IOS, Nokia SR Linux, FRR, FortiGate, Linux. Windows is intentionally
excluded — domain accounts are managed by the `windows_ad` role.

## Variables

| Variable             | Type | Purpose                                       |
|----------------------|------|-----------------------------------------------|
| `aaa_servers`        | list | RADIUS servers: `host`, `secret`, `timeout`   |
| `dot1x`              | dict | `enabled`, `fallback_vlan`, `voice_vlan`      |
| `users_aaa_local`    | list | Break-glass local users: `name`, `role`       |

`aaa_servers` and `dot1x` come from `group_vars/network.yml`. Secrets are
vault-encrypted — never commit plaintext RADIUS secrets.

## Input validation

`tasks/assert.yml` checks the inputs before any device is touched:

- Every `users_aaa_local` account has a non-empty `name` and `role`, and
  account names are unique.
- `dot1x` is a mapping with a boolean `enabled` key.
- `aaa_servers` is a list.

## Example

```yaml
- hosts: network
  roles:
    - role: users_aaa
```

## Known limitations

802.1X is applied globally here; per-port `authentication` settings are the
responsibility of the `interfaces` role.
