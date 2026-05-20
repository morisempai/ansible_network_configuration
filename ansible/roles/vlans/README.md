# vlans

Maintains the VLAN database on every L2-capable device. The VLAN list is a
single source of truth in `group_vars/network.yml`, mirroring the table in
`docs/architecture-brief.md`.

## Supported device classes

Cisco IOS, Nokia SR Linux, FRR, FortiGate.

## Variables

| Variable       | Type | Purpose                              |
|----------------|------|--------------------------------------|
| `vlans`        | list | Each item: `id`, `name`              |

## Example

```yaml
- hosts: network
  roles:
    - role: vlans
```

## Known limitations

Regional `C9200` switches carry every VLAN as trunk to the FortiGate; this
role only ensures the VLAN database — trunk allow-lists are set by the
`interfaces` role.
