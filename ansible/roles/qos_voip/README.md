# qos_voip

Enforces the **voice QoS policy** across the estate: voice traffic on the VoIP
VLAN (60, per `docs/architecture-brief.md`) is given a recognised DSCP marking
and priority treatment so calls survive link congestion.

This role *defines* the QoS policy. It does not bind the policy to interfaces
or firewall policies — see "Scope" below.

## Variables

The role consumes two variables. Both have network-wide defaults from
`group_vars/network.yml`; when `netbox_enabled` is true, `tasks/netbox.yml`
replaces them with the device's NetBox config context. `tasks/assert.yml`
validates them before any device is touched:

| Variable            | Type          | Required | Constraint                                  |
|---------------------|---------------|----------|---------------------------------------------|
| `qos_voip_vlan_id`  | integer       | yes      | 1–4094 (default `60`)                       |
| `qos_voip_marking`  | string (DSCP) | yes      | a DSCP class keyword (default `ef`)          |

`qos_voip_vlan_id` defaults from `qos_voip_vlan` and `qos_voip_marking` from
`qos_voip_dscp`. Because the defaults are templated scalars, a bare integer
default renders as a *string* — `tasks/assert.yml` and every vendor file
coerce the value (`| int`, `| lower`) rather than assuming a type. See
`docs/` notes on the templating gotcha.

### Accepted DSCP markings

`qos_voip_marking` must be one of:

| Keyword          | Meaning                          |
|------------------|----------------------------------|
| `ef`             | Expedited Forwarding (voice)     |
| `cs0`–`cs7`      | Class Selector                   |
| `af11`–`af43`    | Assured Forwarding               |
| `default` / `be` | Best Effort (equivalent to `cs0`)|

The brief specifies `ef` for voice; the wider set is accepted so the role can
serve other priority classes if reused. FortiOS and SR Linux need the numeric
form of the marking — the `fortios` / `srlinux` task files carry the full
keyword → 6-bit / keyword → decimal maps, so any accepted keyword works on
every device class.

```yaml
qos_voip_vlan_id: 60
qos_voip_marking: ef
```

## Supported device classes

| `ansible_network_os` | Behaviour                                                                          |
|----------------------|------------------------------------------------------------------------------------|
| `cisco.ios.ios`      | MQC `class-map VOICE` (matches the voice VLAN) + `policy-map QOS-VOICE` that marks the DSCP and gives voice a strict-priority (LLQ) queue — built with `ios_config` |
| `fortinet.fortios`   | Shared traffic shaper `voice-shaper`: guaranteed bandwidth, high priority, DSCP re-marking via `diffserv`/`diffservcode` |
| `nokia.srlinux`      | `/qos` DSCP classifier policy `voice` mapping the marking to forwarding-class `fc7` (highest priority)                  |
| `frr.frr`            | No-op — QoS on a Linux/FRR host is kernel `tc`, owned by `linux_base`               |
| `cisco.nxos`         | No-op — the MDS 9132T is a Fibre Channel SAN switch with no voice traffic           |

The FortiGate VDOM (`fortios_vdom`, default `root`) can be overridden per
host/group.

## Input validation

`tasks/assert.yml` checks the inputs before any device is touched:

- `qos_voip_vlan_id` is numeric and a valid VLAN id (1–4094) — accepted as an
  int or a numeric string, since the templated default stringifies a scalar.
- `qos_voip_marking` is one of the accepted DSCP class keywords above.

## NetBox source of truth

When `netbox_enabled` is true, `tasks/netbox.yml` resolves the inputs from the
device's **config context** (QoS is not a native NetBox object — see
`docs/netbox.md`):

| Config-context key | Sets                |
|--------------------|---------------------|
| `qos_voip_vlan`    | `qos_voip_vlan_id`  |
| `qos_voip_dscp`    | `qos_voip_marking`  |

Any key NetBox does not supply falls back to the static `group_vars` value.

## Example

```yaml
- hosts: network
  roles:
    - role: vlans       # the VoIP VLAN must exist first
    - role: qos_voip    # then define the voice QoS policy
```

## Scope

- **Policy definition only.** This role builds the QoS *policy object* on each
  device. Attaching it to traffic is intentionally a separate concern:
  - **Cisco IOS** — binding `service-policy output QOS-VOICE` to uplink/trunk
    interfaces is the `interfaces` role's job (it owns interface config).
  - **FortiOS** — referencing `voice-shaper` from a firewall policy
    (`traffic-shaper`) is the `acl_firewall` role's job.
  - **SR Linux** — binding the `voice` dscp-policy to interface inputs is the
    `interfaces` role's job.
  Keeping definition and attachment separate means QoS intent is declared once
  here and applied where each owning role already manages interfaces/policies.
- **No voice-VLAN assignment.** Putting access ports into the voice VLAN is
  the `interfaces` role's responsibility.
- **No pruning.** The role adds/updates the voice policy; it never removes
  other class-maps, shapers, or classifiers.

## Known limitations

- **Device paths are not exercised by CI.** Molecule runs against a plain
  Linux host, where the role validates inputs and resolves to a no-op. The
  Cisco IOS, FortiOS, and SR Linux paths are verified by construction:
  - `cisco.ios.ios_config` parameters were checked with `ansible-doc`.
  - `fortinet.fortios.fortios_firewall_shaper_traffic_shaper` parameters were
    checked with `ansible-doc`.
  - **SR Linux QoS YANG paths cannot be verified with `ansible-doc`** —
    `nokia.srlinux.config` writes raw gNMI paths. The `/qos/classifiers/`
    `dscp-policy` path targets the SR Linux QoS model and assumes a **SR Linux
    23.x or newer** release (the structured `/qos` tree). On older releases
    the path name may differ and the task would need adjusting.
- **Cisco bandwidth percentage is fixed.** The IOS `priority percent 30` and
  the FortiOS shaper bandwidth figures are sensible defaults, not tunable
  inputs. Make them role variables if per-site tuning becomes a requirement.
