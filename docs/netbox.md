# NetBox as the single source of truth

In production and staging, **NetBox is the source of truth for role data.**
Each role resolves its inputs from NetBox at run time instead of from static
files. The Containerlab lab and Molecule keep using static `group_vars`, so
nothing in this design depends on a reachable NetBox during development or CI.

## The layered model

NetBox holds two kinds of data, and roles read each from where it actually
lives:

| Data | Where it lives in NetBox | How a role reads it |
|------|--------------------------|---------------------|
| VLANs, interfaces, IP addressing | Native **IPAM / DCIM** objects | `nb_lookup` query |
| Everything else — ACLs, QoS, NTP/DNS/syslog, AAA, OS hardening, AD | **Config context** (JSON attached to the device) | `config_context` hostvar |

NetBox has no model for an ACL rule or an NTP server list, so that data goes
into a device's **config context** — a JSON document NetBox merges from the
global / site / role / platform / tag levels. The `nb_inventory` plugin
(`config_context: true`) merges the result into each host as the
`config_context` hostvar.

VLANs and interfaces *are* native NetBox objects, so those roles query them
directly with `netbox.netbox.nb_lookup` rather than duplicating them into a
config context.

### What each role sources from NetBox

| Role | NetBox source | Detail |
|------|---------------|--------|
| `vlans` | IPAM — `ipam/vlans` | Network-wide VLAN database (`status=active`) |
| `interfaces` | DCIM — `dcim/interfaces` | Interfaces of the current device |
| `common` | config context | `ntp_servers`, `dns_servers`, `syslog_servers`, `snmp_v3`, `login_banner` |
| `users_aaa` | config context | `aaa_servers`, `dot1x`, `users_aaa_local` |
| `acl_firewall` | config context | `acl_default_action`, `acl_rules` |
| `qos_voip` | config context | `qos_voip_vlan`, `qos_voip_dscp` |
| `l3_routing` | config context | `l3_svis`, `l3_static_routes`, `l3_ospf` |
| `linux_base` | config context | `linux_base_*` hardening / monitoring keys |
| `windows_ad` | config context | `windows_ad_domain`, `windows_ad_is_primary`, `windows_ad_replica_of` |
| `backup_config` | config context | `backup_config_dir`, `backup_config_git_push` (optional) |

Secrets (RADIUS keys, the AD safe-mode password, …) always stay in Ansible
Vault and are **never** sourced from NetBox.

## The toggle: `netbox_enabled`

A single variable, `netbox_enabled`, decides whether roles read from NetBox.
It is driven by **which inventory you run against** — there is no flag to
remember.

```
ansible/inventory/
  lab/      group_vars/all.yml   netbox_enabled: false   (static group_vars)
  staging/  group_vars/all.yml   netbox_enabled: true    (NetBox)
  prod/     group_vars/all.yml   netbox_enabled: true    (NetBox)
```

Ansible auto-loads a `group_vars/` directory that sits next to the inventory
source, so selecting `-i ansible/inventory/prod/netbox.yml` turns NetBox on,
and `-i ansible/inventory/lab/hosts.yml` leaves it off. When the variable is
absent entirely (Molecule), `netbox_enabled | default(false)` makes it off.

This matters because the network has a two-phase bootstrap: you cannot read
from NetBox before NetBox exists. Bootstrap playbooks run with the toggle off
against static data; steady-state runs use the NetBox inventories.

## `group_vars` layout

```
ansible/playbooks/group_vars/      shared, cross-environment static data
  all.yml  network.yml  linux.yml  windows.yml
ansible/inventory/<env>/group_vars/all.yml   per-environment: netbox_enabled,
                                             netbox_url, netbox_token, ...
```

Shared data is **playbook-adjacent** so it loads for every run; per-environment
data is **inventory-adjacent** so it follows the inventory. Both are loaded
automatically by Ansible. (Earlier the shared `group_vars` sat in a directory
Ansible never scanned and silently did nothing — relocating them fixed that.)

## How a role resolves its inputs

Every role's `tasks/main.yml` includes a NetBox resolver as its first step:

```yaml
- name: "Vlans | resolve inputs from NetBox"
  ansible.builtin.include_tasks: netbox.yml
  when: netbox_enabled | default(false) | bool
```

`tasks/netbox.yml` fetches the data and `set_fact`s the role's input
variables. `set_fact` outranks `defaults/` and `group_vars/` in Ansible's
precedence, so NetBox values transparently replace the static ones — and the
rest of the role stays source-agnostic. When the toggle is off, `netbox.yml`
is skipped and the static values stand.

Native-object roles query NetBox directly:

```yaml
# roles/vlans/tasks/netbox.yml
- name: "Vlans | netbox | resolve the VLAN database from NetBox IPAM"
  ansible.builtin.set_fact:
    vlans_config: >-
      {{ query('netbox.netbox.nb_lookup', 'vlans',
               api_endpoint=netbox_url, token=netbox_token,
               validate_certs=netbox_validate_certs,
               api_filter='status=active')
         | community.general.json_query('[].value.{id: vid, name: name}') }}
```

Config-context roles read the merged `config_context` hostvar, falling back to
the static value for any key NetBox does not provide:

```yaml
# roles/common/tasks/netbox.yml
- name: "Common | netbox | resolve baseline inputs from config context"
  ansible.builtin.set_fact:
    common_ntp_servers: "{{ config_context.ntp_servers | default(common_ntp_servers) }}"
    # ...
  when: config_context is defined
```

## Connection settings

The in-role `nb_lookup` queries need their own NetBox connection (the dynamic
inventory plugin is configured separately in `inventory/<env>/netbox.yml`).
These live in the inventory-adjacent `group_vars/all.yml`:

```yaml
netbox_url: "https://netbox.example.internal"
netbox_token: "{{ lookup('ansible.builtin.env', 'NETBOX_TOKEN') }}"
netbox_validate_certs: true
```

The token is read from the `NETBOX_TOKEN` environment variable — supplied by
an AWX credential in production, never committed to disk.

## Populating config context

In the NetBox UI: **Provisioning → Config Contexts**. Attach a context to a
device role, site, platform, or tag and NetBox merges it onto every matching
device. Example context for HQ switches:

```json
{
  "ntp_servers": ["10.0.10.10", "10.0.10.11"],
  "dns_servers": ["10.0.10.20", "10.0.10.21"],
  "syslog_servers": [{"host": "10.0.10.30", "port": 514, "proto": "udp"}],
  "login_banner": "Authorised access only.",
  "acl_default_action": "deny",
  "qos_voip_vlan": 60,
  "qos_voip_dscp": "ef"
}
```

The config-context key names match the static `group_vars` key names exactly —
only the source differs between an environment with the toggle on and one with
it off.

## Adding NetBox support to a new role

1. Add `tasks/netbox.yml` that `set_fact`s the role's input variables — from
   `nb_lookup` if the data is a native NetBox object, otherwise from
   `config_context`.
2. Make `tasks/main.yml` include it first, guarded by
   `when: netbox_enabled | default(false) | bool`.
3. Document the NetBox source and config-context keys in the role's
   `README.md` and in the table above.

See [docs/adding-a-role.md](adding-a-role.md) for the full role template.
