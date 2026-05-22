# acl_firewall

Enforces **access-control and firewall policy** across the estate. The network
is **deny-by-default** (`docs/architecture-brief.md`): every L3 boundary drops
inter-VLAN traffic unless an explicit allow rule exists. This role renders that
baseline posture plus the explicit allow-list on every device class that
filters traffic.

This role declares *what traffic is permitted*. It does not bind ACLs to
interfaces/SVIs (that is the `l3_routing` role's job on Cisco/SR Linux) and it
does not create the VLANs the rules reference (see the `vlans` role).

## Variables

The role consumes two variables. `tasks/assert.yml` validates both before any
device is touched, so a malformed policy fails the run early with a clear
message.

| Variable                     | Type   | Required | Purpose                                            |
|------------------------------|--------|----------|----------------------------------------------------|
| `acl_firewall_default_action`| string | yes      | `allow` or `deny` — baseline for unmatched traffic |
| `acl_firewall_rules`         | list   | yes      | Explicit rule list (see below); may be empty       |

`acl_firewall_default_action` defaults from `acl_default_action`
(`group_vars/network.yml`) so the policy posture lives in one place
network-wide. **Do not change it from `deny` without review.**

Each `acl_firewall_rules` item:

| Field     | Type   | Required | Constraint                                            |
|-----------|--------|----------|-------------------------------------------------------|
| `name`    | string | yes      | non-empty, unique                                     |
| `src`     | string | yes      | source CIDR `a.b.c.d/prefix` (`0.0.0.0/0` for any)    |
| `dst`     | string | yes      | destination CIDR `a.b.c.d/prefix`                     |
| `service` | string | yes      | `tcp/<port>`, `udp/<port>`, `ip` or `icmp`            |
| `action`  | string | yes      | `allow` or `deny`                                     |

```yaml
acl_firewall_default_action: deny
acl_firewall_rules:
  - name: corp-to-servers-https
    src: 10.0.40.0/22
    dst: 10.0.20.0/24
    service: tcp/443
    action: allow
  - name: corp-dns
    src: 10.0.40.0/22
    dst: 10.0.10.20/32
    service: udp/53
    action: allow
```

## Supported device classes

| `ansible_network_os` | Behaviour                                                                                       |
|----------------------|-------------------------------------------------------------------------------------------------|
| `fortinet.fortios`   | Firewall policy — the **primary enforcement point**. One address object per CIDR, one service object per service, one policy per rule, plus a catch-all policy for the default action |
| `cisco.ios.ios`      | Named extended ACL `INTER_VLAN` via `ios_acls` (`state: merged`); CIDRs become address + wildcard bits, services become protocol + destination port match |
| `nokia.srlinux`      | `ipv4-filter[name=inter-vlan]` entries via `nokia.srlinux.config`, plus a catch-all entry for the default action |
| `frr.frr`            | Host `nftables` — a deny-by-default `inet filter forward` chain with per-rule protocol/port matches (notifies `Reload nftables`) |
| `cisco.nxos`         | No-op — the MDS 9132T is a Fibre Channel SAN switch, physically air-gapped from the LAN |

Per-host/group overrides:

- `fortios_vdom` (default `root`) — FortiGate VDOM.
- `fortios_acl_srcintf` / `fortios_acl_dstintf` (default `any`) — the ingress
  and egress interfaces the FortiGate policies are scoped to.

## Input validation

`tasks/assert.yml` checks the inputs before any device is touched:

- `acl_firewall_default_action` is `allow` or `deny`.
- `acl_firewall_rules` is a list.
- Every rule has a non-empty `name`, a syntactically valid CIDR `src` and
  `dst`, a parseable `service`, and an `action` of `allow` or `deny`.
- Rule names are unique.

The CIDR and service checks use regular expressions rather than the
`ansible.utils.ipaddr` filters because `netaddr` is not installed in this
environment (CI or lab); they range-check octets (0–255), prefix (0–32) and
ports (1–65535) without that dependency.

## NetBox source of truth

ACL / firewall policy has no native NetBox model, so when `netbox_enabled` is
true `tasks/netbox.yml` resolves both inputs from the device's **config
context** (`docs/netbox.md`):

| Config-context key   | Sets                          |
|----------------------|-------------------------------|
| `acl_default_action` | `acl_firewall_default_action` |
| `acl_rules`          | `acl_firewall_rules`          |

When the toggle is off (lab, Molecule) the static `defaults/` values stand.

## Example

```yaml
- hosts: network
  roles:
    - role: vlans         # the VLANs the rules reference
    - role: acl_firewall  # then the policy across them
```

## Known limitations

- **No CI coverage of device paths.** Molecule exercises only the plain-Linux
  no-op path; the Cisco IOS, FortiGate and SR Linux paths are correct by
  construction and verified against the Containerlab lab — see `docs/lab.md`.
- **No ACL/interface binding.** This role declares the policy; binding the
  Cisco ACL to an SVI or the SR Linux filter to a subinterface is the
  `l3_routing` role's responsibility. The FortiGate policy needs no binding.
- **No pruning.** Cisco IOS uses `state: merged` — the role adds and updates
  the `INTER_VLAN` ACEs but never deletes unlisted entries. Decommissioning a
  rule is a deliberate, separate action.
- **SR Linux model version.** The `/acl/ipv4-filter` paths target
  SR Linux **23.10 or newer**. `nokia.srlinux.config` takes arbitrary gNMI
  paths, so this cannot be checked with `ansible-doc`; on an older release the
  ACL container path differs and the paths must be revisited.
- **FortiOS `subnet` notation.** The FortiGate address objects pass `src`/`dst`
  in CIDR form; FortiOS 6.0+ accepts CIDR for `firewall address` `subnet`.
- **Architecture invariants not enforced here.** VLAN 50 (critical infra) has
  all internet egress blocked and VLAN 30 (storage) is non-routed and must
  never appear as `src` or `dst`. This role does not fail the run if a rule
  violates those invariants — Batfish in `tests/batfish/` is the intended
  guard.
