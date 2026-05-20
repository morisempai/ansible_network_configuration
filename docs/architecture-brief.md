# Architecture Brief

> Source: pasted from an earlier planning session (web Claude). This is the
> single source of truth for site layout, VLANs, device classes, and pipeline
> design. Update via PR when the design changes.

## Project: Multi-site enterprise network — Ansible automation

### Infrastructure overview

Three sites: **HQ** (primary, hosts all centralized services) and two regional
sites **R1** and **R2**. All inter-VLAN traffic at regional sites hairpins
through the HQ FortiGate for centralized inspection. Regional sites do not
perform local inter-VLAN routing.

### HQ equipment

- Cisco CBS350-8XT — L2 ISP balancer (2 providers → FortiGate)
- FortiGate 200F × 2 — HA pair (active/passive), NGFW, VPN termination, SD-WAN
- Cisco C9300-24UX × 2 — L3 core stack (StackWise-480, STACK-T1-50CM cables),
  uplink module C9300-NM-8X (8 × 10G SFP+)
- Cisco C9200-48P × 2 — L2 access stack (StackWise-160, STACK-T4-50CM cables,
  requires C9200-STACK-KIT)
- HP DL360 Gen10 × 3 — hypervisor cluster (Proxmox or VMware), each with
  2 × FC HBA + 1 × HPE 561T (2 × 10GbE RJ-45 for LAN)
- Cisco MDS 9132T — FC SAN switch (MPIO, 2 paths per server)
- HPE MSA 2062 SFF — SAN array, RAID-6, 20 TB SSD
- Cisco CBS350 management ports connect to dedicated OOB switch
- OOB switch — isolated management VLAN, accessible only via jump host over VPN
- Raritan EMX2-888 — environmental monitoring (temp, humidity, door sensor)
  via SNMP
- 2 × APC SRT6KRMXLI UPS (PDU-A and PDU-B, independent circuits), PowerChute in
  Redundant mode — shutdown only when both UPS are on battery
- 2 × Vertical PDU (0U), managed, SNMP v3

### Regional sites (identical, × 2)

- FortiGate 100F — NGFW, VPN tunnel to HQ, L3 gateway for all VLANs
  (router-on-a-stick). Guest VLAN exits locally to internet (split-tunnel
  policy).
- Cisco C9200-48P — L2 only, all VLANs as trunk to FortiGate
- APC SRT1500RMXLI UPS — single unit sufficient (load ~300 W)
- Vertical PDU (0U), managed
- Raritan EMX2-111 — environmental monitoring

### VLAN scheme (all sites)

| VLAN | Name                 | Subnet            | Notes                                |
|-----:|----------------------|-------------------|--------------------------------------|
|   10 | Management / OOB     | 10.0.10.0/24      | Jump host only                       |
|   20 | Servers / hypervisors| 10.0.20.0/24      | HQ only                              |
|   30 | Storage iSCSI/FC     | 10.0.30.0/24      | No routing, HQ only                  |
|   40 | Corporate users      | 10.0.40.0/22      | All sites                            |
|   50 | Critical infra       | 10.0.50.0/24      | No internet egress                   |
|   60 | VoIP                 | 10.0.60.0/24      | QoS priority                         |
|   70 | Guest WiFi           | 192.168.70.0/24   | Internet only, captive portal OTP    |
|   90 | WAN / inter-site     | 10.0.90.0/30 each | SD-WAN tunnels                       |

**Default inter-VLAN policy: deny all, explicit allow only.**

### Network topology details

- Servers connect to the C9300 stack via cross-stack LACP port-channel
  (1 × 10GbE port per stack member via HPE 561T NIC).
- FC SAN fabric is completely isolated — no routing to any other VLAN.
  Storage switch (MDS 9132T) connects only to server HBAs and the MSA 2062.
  It is physically separate from the LAN.
- OOB management switch connects to: server iLO ports, switch mgmt ports,
  FortiGate MGMT port (dedicated isolated port).
- All management access path:
  `Engineer → VPN → FortiGate → Jump host → OOB switch → device`.

### Authentication and security

- 802.1X NAC on all wired ports (C9300 and C9200) via RADIUS backed by AD
- EAP-TLS (device certificates from internal PKI) preferred,
  PEAP-MSCHAPv2 as fallback
- AD/LDAP primary on HQ, replicas at R1 and R2 for WAN outage resilience
- Port-scan detection and automatic IP blocking on FortiGate IPS
- Guest WiFi: open SSID, captive portal with OTP/SMS, isolated VLAN,
  no corporate access
- Corporate WiFi: WPA3-Enterprise, 802.1X, domain devices only
- Critical infra VLAN: all internet egress blocked at firewall,
  admin access via jump host only
- Physical access control: door ACL based on AD group / IP subnet

### Ansible connection methods

| Device class                     | `ansible_connection`       | Notes                              |
|----------------------------------|----------------------------|------------------------------------|
| Linux servers                    | `ssh`                      | Management VLAN IP                 |
| Windows (AD, DNS, DHCP)          | `winrm`                    | Management VLAN IP                 |
| Cisco C9300, C9200, CBS350       | `network_cli` or `netconf` | Management VLAN IP                 |
| FortiGate                        | `httpapi`                  | MGMT port IP, `fortinet.fortios`   |
| Cisco MDS 9132T                  | `network_cli`              | Management VLAN IP                 |
| HPE iLO (firmware, power)        | iLO REST                   | Over OOB VLAN, `hpe.ilo` collection|
| NetBox (inventory source)        | n/a                        | `netbox.netbox` dynamic inventory  |
| OOB / emergency access           | iLO API directly           | Never routine Ansible runs         |

### Key Ansible collections

- `cisco.ios` — C9300, C9200, CBS350
- `cisco.nxos` — MDS 9132T (SAN OS)
- `fortinet.fortios` — FortiGate 200F and 100F
- `community.windows` — Windows Server / AD
- `microsoft.ad` — Active Directory management
- `netbox.netbox` — dynamic inventory + IPAM source of truth
- `community.zabbix` — Zabbix host registration
- `hpe.ilo` — iLO server management

### IaC pipeline

GitLab CE self-hosted at HQ → GitLab Runner → Ansible AWX → dry-run
(`--check`) → MR approval → apply. NetBox is the single source of truth —
Ansible dynamic inventory reads from the NetBox API. All changes via Git only,
no manual CLI on production devices.

**Bootstrap sequence:** a temporary external runner deploys GitLab + AWX + jump
host on a minimal management VLAN (manually configured), then the self-hosted
pipeline takes over for all remaining configuration.

### Monitoring stack

- Zabbix — node health, UPS status (SNMP), switch metrics, server iLO sensors,
  Raritan EMX temperature/door
- Prometheus + Grafana — optional, hypervisor and VM metrics
- Graylog or ELK — SIEM, log aggregation from all FortiGate, switches, servers
- All monitoring traffic on management VLAN only
- PowerChute Network Shutdown — Redundant mode, both UPS monitored jointly,
  shutdown sequence: user VMs → infra VMs (AD, DNS) → hypervisors → network gear

### Software licenses (required before deployment)

- FortiCare + FortiGuard UTP — annual subscription, all 4 FortiGate devices
- Cisco DNA Essentials — annual subscription, all 6 Cisco Catalyst switches
- Hypervisor — Proxmox subscription (recommended) or VMware vSphere Enterprise
  Plus × 3 hosts
- Windows Server 2022 Datacenter × 2 (HQ primary + replica) — perpetual
- Windows Server CAL — per user, perpetual
- PowerChute Network Shutdown virtualization license — annual
- Cisco MDS Enterprise Package — perpetual
