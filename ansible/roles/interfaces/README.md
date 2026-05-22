# interfaces

Configures **physical interface attributes** — description, admin state, MTU
— and the **Layer-2 mode** (access / trunk / routed) of every switchport.
LACP port-channel membership is handled here too, since bundle membership is
an interface property.

This role configures *ports*. It does not create VLANs (see the `vlans`
role) or assign IP addresses / SVIs (see `l3_routing`).

## Variables

The role consumes one variable, `interfaces_config`. It has no network-wide
default — interfaces are per-device — so values come from host_vars, or from
NetBox DCIM when `netbox_enabled` is true. `tasks/assert.yml` validates it
before any device is touched:

| Field           | Type    | Required | Constraint                      |
|-----------------|---------|----------|---------------------------------|
| `name`          | string  | yes      | non-empty, unique               |
| `description`   | string  | no       | —                               |
| `enabled`       | boolean | no       | default `true`                  |
| `mtu`           | integer | no       | positive                        |
| `mode`          | string  | no       | `access` \| `trunk` \| `routed` |
| `access_vlan`   | integer | no       | 1–4094, with `mode: access`     |
| `trunk_vlans`   | list    | no       | integers, with `mode: trunk`    |
| `channel_group` | integer | no       | positive — LACP bundle id       |

```yaml
interfaces_config:
  - name: GigabitEthernet1/0/1
    description: server uplink
    mtu: 9100
    mode: trunk
    trunk_vlans: [10, 20, 40]
    channel_group: 1
  - name: GigabitEthernet1/0/24
    description: user port
    mode: access
    access_vlan: 40
```

## Supported device classes

| `ansible_network_os` | Behaviour                                                     |
|----------------------|---------------------------------------------------------------|
| `cisco.ios.ios`      | Physical attrs (`ios_interfaces`), L2 mode (`ios_l2_interfaces`), `no switchport` for routed ports, LACP (`ios_lag_interfaces`) |
| `nokia.srlinux`      | Physical attrs on `/interface`; bridged subinterfaces bound to the per-VLAN `mac-vrf` network-instances |
| `fortinet.fortios`   | Physical port attrs only — VLANs are tagged sub-interfaces (the `vlans` role) |
| `frr.frr`            | No-op — interface attrs on a Linux/FRR host are kernel objects (`linux_base`) |
| `cisco.nxos`         | No-op — the MDS 9132T is a Fibre Channel SAN switch, no Ethernet interfaces |

The FortiGate VDOM (`fortios_vdom`, default `root`) can be overridden per
host/group.

## Input validation

`tasks/assert.yml` checks `interfaces_config` before any device is touched:

- Every interface has a non-empty, unique `name`.
- Optional fields, where present, are well-typed (see the table above).

## LACP

`channel_group` declares LACP bundle membership. Servers attach to the HQ
C9300 stack via **cross-stack port-channels** — one member port per stack
member (`docs/architecture-brief.md`). Express this as one `interfaces_config`
entry per physical member port, all sharing the same `channel_group` id; the
role does not infer stack topology. Member ports join the bundle as LACP
active, and the `Port-channelN` logical interface is created on demand.

## Example

```yaml
- hosts: network
  roles:
    - role: vlans       # create the VLANs first
    - role: interfaces  # then bind ports to them
```

## Scope

- **Ports only.** VLAN creation is the `vlans` role; IP addressing / SVIs the
  `l3_routing` role.
- **Routed ports.** `mode: routed` removes the port from switching
  (`no switchport` on Cisco IOS); the IP address is set by `l3_routing`.
- **Ordering on SR Linux.** Binding a port to a VLAN needs that VLAN's
  `mac-vrf` network-instance to exist — run the `vlans` role first.
- **No pruning.** Cisco IOS uses `state: merged`; the role adds and updates
  the listed interfaces but never resets unlisted ports.
