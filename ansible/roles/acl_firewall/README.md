# acl_firewall

Access-control and firewall policy. The estate is **deny-by-default**: every
L3 boundary drops inter-VLAN traffic unless an explicit allow rule exists.
This role renders that baseline plus the explicit allow-list.

## Supported device classes

Cisco IOS (ACLs), Nokia SR Linux (ACLs), FRR (host nftables via Linux), and
FortiGate (firewall policy — the primary enforcement point).

## Variables

| Variable                  | Type   | Purpose                               |
|---------------------------|--------|---------------------------------------|
| `acl_default_action`      | string | `deny` (do not change without review) |
| `acl_firewall_rules`      | list   | Explicit allow rules (see below)      |

Each `acl_firewall_rules` item:

```yaml
- name: corp-to-servers-https
  src: 10.0.40.0/22
  dst: 10.0.20.0/24
  service: tcp/443
  action: allow
```

## Example

```yaml
- hosts: network
  roles:
    - role: acl_firewall
```

## Known limitations

VLAN 50 (critical infra) has **all internet egress blocked**. VLAN 30
(storage) is non-routed and must never appear as `src` or `dst`. The role
does not currently fail the run if these invariants are violated — Batfish in
`tests/batfish/` is the intended guard.
