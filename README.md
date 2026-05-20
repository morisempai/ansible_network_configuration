# ansible_network_configuration

Vendor-agnostic Ansible automation for a three-site enterprise network
(HQ + R1 + R2). See [docs/architecture-brief.md](docs/architecture-brief.md)
for the authoritative description of the target infrastructure.

## Design principle: vendor-agnostic roles

Every role exposes the **same variable interface** (e.g. `interfaces:`,
`vlans:`, `aaa_servers:`). The role's `tasks/main.yml` dispatches to a
vendor-specific implementation based on the host's `ansible_network_os`
(Cisco IOS, Nokia SR Linux, FRR, FortiGate, Linux, Windows).

```
roles/<role>/
  tasks/main.yml          # picks include_tasks based on ansible_network_os
  tasks/cisco_ios.yml     # Cisco IOS / IOS-XE implementation
  tasks/srlinux.yml       # Nokia SR Linux implementation
  tasks/frr.yml           # FRRouting implementation
  tasks/fortios.yml       # FortiGate implementation
  tasks/linux.yml         # Generic Linux implementation
  tasks/windows.yml       # Windows / AD implementation
```

The interface is shared; the implementations are not. This is the most
pragmatic balance for a heterogeneous estate that includes Cisco IOS classic
and FortiGate, neither of which speak OpenConfig cleanly.

## Repository layout

```
.
├── README.md                  # you are here
├── docs/
│   ├── architecture-brief.md  # SOT for site/VLAN/device design
│   ├── adding-a-role.md       # how to add a new role to this repo
│   ├── lab.md                 # how to run the Containerlab test lab
│   └── testing.md             # full testing strategy (lint → lab → prod)
├── .github/
│   ├── workflows/             # lint, molecule, lab CI pipelines
│   └── PULL_REQUEST_TEMPLATE.md
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml       # Ansible collections
│   ├── requirements.txt       # Python dependencies
│   ├── inventory/
│   │   ├── lab/               # static inventory for the Containerlab topology
│   │   ├── staging/           # NetBox dynamic inventory (staging instance)
│   │   └── prod/              # NetBox dynamic inventory (production)
│   ├── group_vars/            # cross-cutting variables per device class
│   ├── host_vars/             # per-host overrides
│   ├── playbooks/             # site.yml, bootstrap.yml, per-class playbooks
│   └── roles/                 # 10 vendor-agnostic roles (see below)
├── lab/
│   ├── topology.clab.yml      # Containerlab topology (SR Linux + FRR + Linux)
│   └── deploy.sh              # ./lab/deploy.sh up | down | status
└── tests/
    ├── batfish/               # pre-deploy config analysis (planned)
    └── testinfra/             # pytest post-deploy assertions (planned)
```

## Roles

| Role            | Purpose                                                   |
|-----------------|-----------------------------------------------------------|
| `common`        | Hostname, NTP, DNS, syslog, SNMP, login banner            |
| `users_aaa`     | Local users, AAA (RADIUS/TACACS+), 802.1X RADIUS clients  |
| `interfaces`    | Physical interface attributes (description, MTU, speed)   |
| `vlans`         | VLAN database + access/trunk port assignment              |
| `l3_routing`    | SVIs, static routes, dynamic routing (HQ core only)       |
| `acl_firewall`  | Access lists / firewall policy (deny-by-default)          |
| `qos_voip`      | QoS classification and queuing for the VoIP VLAN          |
| `linux_base`    | Base hardening + monitoring agent for Linux servers       |
| `windows_ad`    | Base config + AD role for Windows servers                 |
| `backup_config` | Pull running-config from network devices to a git repo    |

Each role lives under `ansible/roles/<name>/` and has its own README.

## Getting started

```bash
# 1. Install tooling (one-time)
python3 -m pip install -r ansible/requirements.txt
ansible-galaxy collection install -r ansible/requirements.yml
pre-commit install

# 2. Spin up the lab
./lab/deploy.sh up

# 3. Run a playbook in check mode against the lab
ansible-playbook -i ansible/inventory/lab/hosts.yml \
  ansible/playbooks/site.yml --check --diff

# 4. Tear the lab down
./lab/deploy.sh down
```

See [docs/lab.md](docs/lab.md) for full lab instructions and
[docs/testing.md](docs/testing.md) for the broader testing strategy.

## Workflow

- Do not commit to `main`. Open a PR from a feature branch.
- All PRs run `yamllint`, `ansible-lint`, and `molecule test` for any role
  touched by the PR.
- Production runs are dispatched from AWX after MR approval, never from a
  laptop.

## Adding a new role

See [docs/adding-a-role.md](docs/adding-a-role.md) for the role template and
Molecule scenario boilerplate.
