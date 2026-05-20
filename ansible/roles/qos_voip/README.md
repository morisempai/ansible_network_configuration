# qos_voip

Quality-of-service for the VoIP VLAN (60): traffic classification and
priority queuing so voice survives congestion.

## Supported device classes

Cisco IOS, Nokia SR Linux, FRR, FortiGate.

## Variables

| Variable           | Type   | Purpose                                   |
|--------------------|--------|-------------------------------------------|
| `qos_voip_vlan`    | int    | VLAN carrying voice traffic (default 60)  |
| `qos_voip_dscp`    | string | DSCP marking for voice (default `ef`)     |

Both come from `group_vars/network.yml`.

## Example

```yaml
- hosts: network
  roles:
    - role: qos_voip
```

## Known limitations

This role marks and queues voice traffic; it does not configure the voice
VLAN assignment on access ports — that is the `interfaces` role's job.
