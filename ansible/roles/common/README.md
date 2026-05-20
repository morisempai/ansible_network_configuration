# common

Baseline configuration applied to **every** managed device: hostname, NTP,
DNS, syslog, SNMP, and the login banner.

## Supported device classes

| Class            | `ansible_network_os`         | Implementation file        |
|------------------|------------------------------|----------------------------|
| Cisco IOS / IOS-XE | `cisco.ios.ios`            | `tasks/cisco_ios.yml`      |
| Cisco NX-OS / MDS | `cisco.nxos.nxos`           | `tasks/cisco_nxos.yml`     |
| Nokia SR Linux   | `nokia.srlinux.srlinux`      | `tasks/srlinux.yml`        |
| FRRouting        | `frr.frr.frr`                | `tasks/frr.yml`            |
| FortiGate        | `fortinet.fortios.fortios`   | `tasks/fortios.yml`        |
| Linux            | (uses `ansible_os_family`)   | `tasks/linux.yml`          |
| Windows          | (uses `ansible_os_family`)   | `tasks/windows.yml`        |

## Variables

Consumed from `group_vars/all.yml`:

| Variable          | Type   | Purpose                                |
|-------------------|--------|----------------------------------------|
| `org_name`        | string | Used in banner and SNMP location       |
| `org_domain`      | string | Used in hostname / search domain       |
| `ntp_servers`     | list   | NTP server IPs                         |
| `dns_servers`     | list   | DNS resolver IPs                       |
| `syslog_servers`  | list   | Each item: `host`, `port`, `proto`     |
| `snmp_v3`         | dict   | `user`, `auth_proto`, `priv_proto`     |
| `login_banner`    | string | Multi-line banner text                 |

## Example

```yaml
- hosts: network
  roles:
    - role: common
```

## Known limitations

The Windows implementation currently sets only NTP and the message-of-the-day;
SNMP on Windows is handled by the `windows_ad` role since it depends on the
domain join state.
