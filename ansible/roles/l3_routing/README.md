# l3_routing

Layer-3 configuration: SVIs, static routes, and dynamic routing. Applied
**only** to devices in the `l3` inventory group — the HQ C9300 core and the
FortiGate gateways. Regional C9200 switches are L2-only and never receive
this role (see the `when` guard in `playbooks/network.yml`).

## Supported device classes

Cisco IOS, Nokia SR Linux, FRR, FortiGate.

## Variables

| Variable               | Type | Purpose                                  |
|------------------------|------|------------------------------------------|
| `l3_routing_svis`      | list | SVIs: `vlan_id`, `address`, `description`|
| `l3_routing_static`    | list | Static routes: `prefix`, `next_hop`      |
| `l3_routing_ospf`      | dict | OSPF process id + areas (optional)       |

## Input validation

`tasks/assert.yml` checks the inputs before any device is touched:

- Every `l3_routing_svis` item has an integer `vlan_id` in 1–4094 and a
  non-empty `address`.
- Every `l3_routing_static` item has a non-empty `prefix` and `next_hop`.
- `l3_routing_ospf` is a mapping.

## Example

```yaml
- hosts: l3
  roles:
    - role: l3_routing
```

## Known limitations

Storage VLAN 30 must never receive an SVI — it is intentionally non-routed.
The role does not enforce this; keep VLAN 30 out of `l3_routing_svis`.
