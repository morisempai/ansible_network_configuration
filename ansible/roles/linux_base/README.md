# linux_base

Base hardening and monitoring for Linux servers (DL360 hypervisors, jump
host, monitoring nodes).

## Supported device classes

Linux only.

## What it does

- SSH hardening: disable root login, disable password auth.
- Restrict `sudo` to approved groups.
- Install and configure the Zabbix agent pointed at the management VLAN.
- Apply a minimal `nftables` host firewall.

## Variables

| Variable                         | Type | Purpose                          |
|-----------------------------------|------|----------------------------------|
| `linux_base_disable_root_ssh`     | bool | Disable `PermitRootLogin`        |
| `linux_base_password_auth`        | bool | Allow SSH password auth          |
| `linux_base_allow_sudo_groups`    | list | Groups granted sudo              |
| `linux_base_install_zabbix_agent` | bool | Install + enable Zabbix agent    |
| `linux_base_zabbix_server`        | str  | Zabbix server IP                 |

Defined in `group_vars/linux.yml`.

## Example

```yaml
- hosts: linux
  roles:
    - role: linux_base
```
