# lab/

[Containerlab](https://containerlab.dev/) test topology for the project.
A miniature of the HQ + R1 + R2 estate, built entirely from container images
that run on GitHub-hosted runners — no nested virtualisation, no licensed
images.

## Files

| File                | Purpose                                          |
|---------------------|--------------------------------------------------|
| `topology.clab.yml` | Containerlab topology definition                 |
| `deploy.sh`         | `up` / `down` / `status` wrapper                 |

The Ansible inventory for the lab lives at
`ansible/inventory/lab/hosts.yml` and its host names match the
Containerlab-assigned names (`clab-ansnet-<node>`).

## Topology

```
            hq-linux01 (multitool)
                  |
   hq-access --- hq-core --- r1-edge
   (FRR)        (SR Linux)   (SR Linux)
                  |
               r2-edge (FRR)
```

| Node         | Image                                | Stand-in for         |
|--------------|--------------------------------------|----------------------|
| `hq-core`    | `ghcr.io/nokia/srlinux:latest`       | C9300 L3 core        |
| `r1-edge`    | `ghcr.io/nokia/srlinux:latest`       | C9200 / FortiGate    |
| `hq-access`  | `quay.io/frrouting/frr:latest`       | C9200 L2 access      |
| `r2-edge`    | `quay.io/frrouting/frr:latest`       | regional switch      |
| `hq-linux01` | `ghcr.io/hellt/network-multitool`    | DL360 hypervisor     |

## Usage

```bash
./lab/deploy.sh up        # deploy (installs Containerlab on first run)
./lab/deploy.sh status    # list nodes
./lab/deploy.sh down      # destroy and clean up
```

Run a playbook against the lab:

```bash
ansible-playbook -i ansible/inventory/lab/hosts.yml \
  ansible/playbooks/site.yml --check --diff
```

## Limitations

- **FRR** nodes do not expose SSH/`network_cli` out of the box. They are in
  the topology for link/topology variety; role-level testing against FRR
  uses Molecule's delegated mode rather than live CLI. See
  [../docs/testing.md](../docs/testing.md).
- **FortiGate, Cisco IOS, Windows** are not simulated here — they need
  licensed or KVM-only images. Their roles are still linted, syntax-checked,
  and dispatch-tested; full validation happens on staging hardware.
