# vlans

Enforces the **VLAN database** on every device in the estate. The VLAN list
is a single source of truth — `group_vars/network.yml` for static runs,
NetBox IPAM when `netbox_enabled` is true — mirroring the table in
`docs/architecture-brief.md`.

This role declares *that VLANs exist*. It does not assign access/trunk
ports or VLAN IPs — see "Scope" below.

## Variables

The role consumes one variable, `vlans_config` (defaulted from `vlans`).
`tasks/assert.yml` validates it before any device is touched:

| Field  | Type    | Required | Constraint        |
|--------|---------|----------|-------------------|
| `id`   | integer | yes      | 1–4094, unique    |
| `name` | string  | yes      | non-empty         |

```yaml
vlans:
  - id: 10
    name: management
  - id: 60
    name: voip
```

## Supported device classes

| `ansible_network_os` | Behaviour                                                    |
|----------------------|--------------------------------------------------------------|
| `cisco.ios.ios`      | VLAN database via `ios_vlans` (`state: merged`)              |
| `nokia.srlinux`      | One `mac-vrf` network-instance per VLAN                      |
| `fortinet.fortios`   | One tagged VLAN sub-interface per VLAN on the LAN port       |
| `frr.frr`            | No-op — VLANs are kernel bridge objects (`linux_base`)       |
| `cisco.nxos`         | No-op — the MDS 9132T is a Fibre Channel SAN switch          |

The FortiGate `interface` parent (`fortios_vlan_parent`, default `lan`) and
`fortios_vdom` (default `root`) can be overridden per host/group.

## Example

```yaml
- hosts: network
  roles:
    - role: vlans
```

## Scope

- **VLAN database only.** Trunk allow-lists and access-port assignment are
  set by the `interfaces` role; SVIs/VLAN IPs by `l3_routing`.
- **No pruning.** `state: merged` on Cisco IOS adds and updates the listed
  VLANs but never deletes VLAN 1 or unlisted VLANs. Decommissioning a VLAN
  is a deliberate, separate action.
- **No per-site filtering yet.** `group_vars/network.yml` carries the full
  network-wide list; VLANs 20/30 are HQ-only per the brief. Per-site
  scoping is handled by NetBox in staging/prod.
