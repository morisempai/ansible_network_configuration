# interfaces

Physical interface attributes: description, admin state, MTU, speed/duplex,
and L2 mode (access/trunk). Port-channel (LACP) membership is also handled
here since it is an interface property.

## Supported device classes

Cisco IOS, Nokia SR Linux, FRR, FortiGate.

## Variables

| Variable               | Type | Purpose                                    |
|------------------------|------|--------------------------------------------|
| `interfaces_config`    | list | Per-interface settings (see below)         |

Each `interfaces_config` item:

```yaml
- name: GigabitEthernet1/0/1
  description: uplink to core
  enabled: true
  mtu: 9100
  mode: trunk          # access | trunk | routed
  access_vlan: 40      # when mode == access
  trunk_vlans: [10,20,40,60]  # when mode == trunk
  channel_group: 1     # optional LACP bundle id
```

Interface lists are normally generated from NetBox; the static form above is
for the lab and Molecule.

## Example

```yaml
- hosts: network
  roles:
    - role: interfaces
```

## Known limitations

Cross-stack LACP (1 member port per stack member) must be expressed as
explicit `channel_group` entries — the role does not infer stack topology.
