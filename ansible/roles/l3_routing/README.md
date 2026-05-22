# l3_routing

Configures **Layer-3 routing** on the devices that perform it: routed VLAN
interfaces (SVIs), static routes, and OSPF. Applied **only** to devices in
the `l3` inventory group — the HQ Cisco core and the FortiGate gateways.
Regional C9200 switches are L2-only and never receive this role (see the
`when: "'l3' in group_names"` guard in `playbooks/network.yml`).

This role assigns *Layer-3 addressing and routing*. It does not create
VLANs (see the `vlans` role) or configure switchports (see `interfaces`).

## Variables

The role consumes three variables. All come from the device's `host_vars`
for static runs, or from the NetBox config context when `netbox_enabled` is
true. `tasks/assert.yml` validates every one before any device is touched.

### `l3_routing_svis` — routed VLAN interfaces

| Field         | Type    | Required | Constraint                          |
|---------------|---------|----------|-------------------------------------|
| `vlan_id`     | integer | yes      | 1–4094, unique                      |
| `address`     | string  | yes      | `host/prefix` CIDR (e.g. `10.0.40.1/22`) |
| `description` | string  | no       | non-empty when present              |

### `l3_routing_static` — static routes

| Field      | Type   | Required | Constraint                              |
|------------|--------|----------|-----------------------------------------|
| `prefix`   | string | yes      | CIDR (e.g. `0.0.0.0/0`)                 |
| `next_hop` | string | yes      | IPv4 address                            |
| `device`   | string | no       | FortiGate egress interface — see below  |

### `l3_routing_ospf` — OSPF profile

A mapping. An empty mapping (the default) disables OSPF entirely.

| Field        | Type    | Required | Constraint                  |
|--------------|---------|----------|-----------------------------|
| `process_id` | integer | no       | positive, default `1`       |
| `areas`      | list    | no       | list of `{network, area}`   |

Each `areas` entry: `network` is a CIDR to advertise, `area` is the OSPF
area id (`0`, `0.0.0.0`, …).

```yaml
l3_routing_svis:
  - vlan_id: 40
    address: 10.0.40.1/22
    description: corp users gateway
l3_routing_static:
  - prefix: 0.0.0.0/0
    next_hop: 10.0.90.1
    device: wan1
l3_routing_ospf:
  process_id: 1
  areas:
    - network: 10.0.40.0/22
      area: 0
```

## Supported device classes

| `ansible_network_os` | Behaviour                                                                                  |
|----------------------|--------------------------------------------------------------------------------------------|
| `cisco.ios.ios`      | `Vlan<id>` SVIs (`ios_l3_interfaces` + `ios_interfaces` for the description), static routes (`ios_static_routes`), OSPF (`ios_ospfv2`) |
| `fortinet.fortios`   | SVI = gateway IP on the `vlan<id>` sub-interface (`fortios_system_interface`), static routes (`fortios_router_static`), OSPF (`fortios_router_ospf`) |
| `nokia.srlinux`      | SVI = `irb0.<id>` subinterface bound to the per-VLAN mac-vrf, static routes via a defined next-hop-group, OSPF instance under the default network-instance |
| `frr.frr`            | Static routes and OSPF via `cli_config`; SVIs are kernel interfaces — no-op deferring to `linux_base` |
| `cisco.nxos`         | No-op — the MDS 9132T is a Fibre Channel SAN switch, no IP routing |

The FortiGate VDOM (`fortios_vdom`, default `root`) can be overridden per
host/group.

### How an SVI is expressed per vendor

The architecture has two L3 designs (`docs/architecture-brief.md`):

- **HQ Cisco core** does inter-VLAN routing with classic SVIs — a `Vlan<id>`
  interface carrying the gateway IP.
- **Regional FortiGates** are router-on-a-stick: each VLAN is a tagged
  sub-interface. The `vlans` role creates the `vlan<id>` sub-interface; this
  role assigns its gateway IP. There is no separate SVI object.

On **SR Linux** the equivalent is an `irb` (integrated routing and bridging)
subinterface bound into the per-VLAN `mac-vrf` network-instance. On **FRR**
an SVI is a kernel VLAN interface owned by the host network stack
(`linux_base`); FRR only routes over it once it exists.

## Input validation

`tasks/assert.yml` checks all three inputs before any device is touched:

- Every SVI has an integer `vlan_id` (1–4094, unique) and a CIDR `address`.
- Every static route has a CIDR `prefix` and an IPv4 `next_hop`.
- `l3_routing_ospf` is a mapping; `process_id`, if set, is a positive
  integer; every `areas` entry has a CIDR `network` and an `area` id.

Address fields are validated with a regex rather than `ansible.utils.ipaddr`
because the assert also runs on the plain Linux Molecule host, where the
`netaddr` library `ipaddr` needs is not guaranteed to be installed. The
regex catches malformed input (missing mask, junk) without that dependency.

`process_id` is coerced with `| int` before its numeric check — templated
scalar defaults render as strings, so a string-vs-int comparison would
otherwise spuriously fail.

## NetBox source of truth

SVIs, static routes and the OSPF profile are routing *intent* — NetBox has
no native model for them — so they come from the device's **config
context** (`docs/netbox.md`):

| Role variable        | Config-context key  |
|----------------------|---------------------|
| `l3_routing_svis`    | `l3_svis`           |
| `l3_routing_static`  | `l3_static_routes`  |
| `l3_routing_ospf`    | `l3_ospf`           |

When `netbox_enabled` is false (lab, Molecule) `tasks/netbox.yml` never
runs and the `host_vars` / `defaults` values stand.

## Example

```yaml
- hosts: l3
  roles:
    - role: vlans        # create the VLANs first
    - role: interfaces   # then the ports
    - role: l3_routing   # then L3 addressing and routing
```

## Known limitations

- **Storage VLAN 30 must never receive an SVI.** It is intentionally
  non-routed and air-gapped (`docs/architecture-brief.md`). The role does
  not enforce this — keep VLAN 30 out of `l3_routing_svis`.
- **OSPF scope.** OSPF is implemented for every device class that can run
  it: Cisco IOS, FortiGate, SR Linux and FRR. The MDS 9132T (`cisco.nxos`)
  does no IP routing, so OSPF — like the rest of the role — is a no-op
  there. `l3_routing_ospf` is consumed, never silently dropped.
- **No pruning.** Cisco IOS uses `state: merged`; FortiGate and SR Linux
  updates are additive. The role adds and updates the listed objects but
  never removes SVIs, routes or OSPF networks that are no longer listed.
  Decommissioning is a deliberate, separate action.
- **OSPF area model differs by vendor.** Cisco IOS and FRR use `network …
  area` statements; FortiGate and SR Linux attach interfaces to areas. The
  role feeds each its native shape from the same `l3_routing_ospf.areas`
  list — on SR Linux the `network` field documents intent but areas are
  realised through the `irb` subinterfaces.
- **Device paths are not CI-tested.** Only the Linux no-op path runs under
  Molecule. The Cisco / FortiGate / SR Linux / FRR paths are correct by
  construction (every module verified against `ansible-doc`; SR Linux gNMI
  paths follow the SR Linux >= 23.3 model used across this repo) and are
  exercised against the Containerlab lab — see `docs/lab.md`.
- **OSPF prefix-mask tables.** Neither `ios_ospfv2` nor FortiOS accepts a
  CIDR for an OSPF network — Cisco IOS wants `address` + `wildcard_bits`,
  FortiOS wants `<address> <netmask>`. `tasks/cisco_ios.yml` and
  `tasks/fortios.yml` each carry a CIDR-length → mask table covering the
  lengths the VLAN scheme uses (`/8`–`/32`); a prefix length outside a
  table needs a new entry.
