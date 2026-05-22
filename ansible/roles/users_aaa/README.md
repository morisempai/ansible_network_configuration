# users_aaa

Configures **AAA** — the RADIUS servers wired 802.1X NAC authenticates
against and the global 802.1X switch settings — and the **break-glass local
accounts** that are the RADIUS-independent way back in when every RADIUS
server is unreachable.

This role declares *that the RADIUS servers exist and 802.1X is on*. It does
not set per-port `authentication` configuration — that is the `interfaces`
role's job (see "Scope" below).

## Variables

The role consumes three variables. `tasks/assert.yml` validates all three
before any device is touched.

### `users_aaa_servers` — RADIUS servers

Defaulted from the network-wide `aaa_servers` list in
`group_vars/network.yml`. A list of objects:

| Field     | Type    | Required | Constraint                       |
|-----------|---------|----------|----------------------------------|
| `host`    | string  | yes      | non-empty, unique (IP or name)   |
| `secret`  | string  | yes      | non-empty — Vault-encrypted      |
| `timeout` | integer | no       | positive, default `5`            |

### `users_aaa_dot1x` — wired 802.1X

Defaulted from the network-wide `dot1x` mapping in `group_vars/network.yml`.
A mapping; `enabled` is the only key this role reads.

| Field     | Type    | Required | Constraint |
|-----------|---------|----------|------------|
| `enabled` | boolean | yes      | —          |

### `users_aaa_local` — break-glass local accounts

Per-device or per-group; defaults to a single `netadmin` admin account so a
device is never left without a local way in. A list of objects:

| Field      | Type   | Required | Constraint                            |
|------------|--------|----------|---------------------------------------|
| `name`     | string | yes      | non-empty, unique                     |
| `role`     | string | yes      | non-empty (`admin` grants sudo)       |
| `password` | string | no       | Vault-encrypted hash — see "Secrets"  |

```yaml
aaa_servers:
  - host: 10.0.10.40
    secret: "{{ vault_radius_secret }}"
    timeout: 5
  - host: 10.0.10.41
    secret: "{{ vault_radius_secret }}"

dot1x:
  enabled: true

users_aaa_local:
  - name: netadmin
    role: admin
    password: "{{ vault_netadmin_hash }}"
```

## Secrets

RADIUS `secret` values and local-account `password` hashes are **always**
Vault-encrypted and **never** sourced from NetBox — never commit a plaintext
secret. Every task that handles a secret carries `no_log: true`, including
the schema check in `tasks/assert.yml`.

Passwords are never defaulted: a local account is given a password only when
the caller supplies a `password` hash on the entry. An account without one is
created locked on Linux (`update_password: on_create`, so an existing
password is never re-applied).

## Supported device classes

| `ansible_network_os` | Behaviour                                                       |
|----------------------|-----------------------------------------------------------------|
| `cisco.ios.ios`      | `radius server` blocks + `aaa group server radius` + global AAA / `dot1x system-auth-control`, all via `ios_config` |
| `nokia.srlinux`      | RADIUS `server-group` of type `radius` with one keyed `server` per host; `radius`-then-`local` authentication method |
| `fortinet.fortios`   | One `user_radius` entry per RADIUS server (`fortios_user_radius`) |
| `frr.frr`            | No-op — FRR AAA is delegated to host PAM (`linux_base`)          |
| `cisco.nxos`         | No-op — the MDS 9132T is an air-gapped FC SAN switch            |
| Linux (`linux.yml`)  | Break-glass local accounts via `ansible.builtin.user`; `admin` role joins the `sudo` group |

The SR Linux network-instance for RADIUS reachability (`srlinux_aaa_netinst`,
default `mgmt`) and the FortiGate VDOM (`fortios_vdom`, default `root`) can be
overridden per host/group.

## NetBox source of truth

When `netbox_enabled` is true, `tasks/netbox.yml` resolves the inputs from
the device's merged **config context** (AAA has no native NetBox model),
reading the keys `aaa_servers`, `dot1x` and `users_aaa_local`. Any key NetBox
does not supply falls back to the static default. The config context carries
only non-secret attributes; RADIUS secrets and account password hashes are
layered in from Vault-encrypted `group_vars`/`host_vars` and survive the
NetBox `set_fact`. See `docs/netbox.md`.

## Input validation

`tasks/assert.yml` checks all three variables before any device is touched:

- `users_aaa_servers` is a list; every server has a non-empty `host` and
  `secret` (so per-vendor files can rely on `item.host` / `item.secret`),
  a positive `timeout` if present, and hosts are unique.
- `users_aaa_dot1x` is a mapping with a boolean `enabled` key.
- Every `users_aaa_local` account has a non-empty `name` and `role`, and
  account names are unique.

Type checks coerce with `| string` / `| int` first: templated scalar
defaults can render as strings, so a bare `is integer` test would be unsafe.

## Example

```yaml
- hosts: network
  roles:
    - role: users_aaa
```

## Scope and known limitations

- **No per-port 802.1X.** This role enables 802.1X globally
  (`dot1x system-auth-control` and the method lists). Per-port
  `authentication` / `access-session` configuration is the `interfaces`
  role's responsibility.
- **No pruning.** Cisco IOS uses `ios_config` and SR Linux uses an `update`
  transaction: the role adds and updates the listed RADIUS servers and
  accounts but never removes servers or accounts that are no longer listed.
  Decommissioning is a deliberate, separate action.
- **Break-glass local accounts run on the Linux path only.** `users_aaa_local`
  is consumed by `linux.yml`. Local accounts on Cisco IOS / SR Linux are
  intentionally out of scope here — their device authentication is RADIUS
  with a `local` fallback, and provisioning hashed local credentials on those
  platforms is left to a dedicated change rather than defaulted by this role.
- **No TACACS+.** Only RADIUS is implemented, matching the architecture brief
  (802.1X NAC via RADIUS backed by AD).
- **Windows is excluded.** Domain accounts are managed by the `windows_ad`
  role.
- **SR Linux gNMI paths are a version assumption.** `nokia.srlinux.config`
  exposes no schema to `ansible-doc`, so the `/system/aaa` paths in
  `tasks/srlinux.yml` (`server-group`, `server[address=...]`, `radius`
  container, `authentication-method`) cannot be verified offline. They are
  modelled on the SR Linux 24.x `srl_nokia-aaa` YANG tree; confirm against
  the running NOS version before a production rollout.
- **Device paths are not exercised by CI.** Only the Linux path runs under
  Molecule (the plain Debian host resolves to `linux.yml`). The Cisco IOS,
  FortiGate and SR Linux paths are verified against the Containerlab lab —
  see `docs/lab.md`.
