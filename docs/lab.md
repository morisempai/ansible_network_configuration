# Test Lab

The lab is a [Containerlab](https://containerlab.dev/) topology that runs
entirely in containers — no nested virtualisation, no licensed images. It
runs both locally on Linux/WSL and on GitHub-hosted runners.

## What the lab models

| Logical role                 | Container image                        | Stand-in for           |
|------------------------------|----------------------------------------|------------------------|
| HQ core / regional edge      | `ghcr.io/nokia/srlinux:latest`         | Cisco C9300 / C9200    |
| HQ access / lab switch       | `quay.io/frrouting/frr:latest`         | Linux-based switch     |
| Linux server                 | `ghcr.io/hellt/network-multitool`      | DL360 hypervisor       |
| Test client                  | `alpine:latest`                        | Corporate workstation  |

FortiGate, Windows, and HPE iLO are **not** simulated — they require licensed
or KVM-only images. Roles for those device classes are still lintable and
syntax-checkable; full Molecule scenarios for them are gated behind a manual
job that runs on a real lab.

## Prerequisites

```bash
# Docker (or compatible runtime)
docker --version

# Containerlab
bash -c "$(curl -sL https://get.containerlab.dev)"
containerlab version
```

GitHub-hosted runners already have Docker. The lab CI workflow installs
Containerlab on demand.

## Bringing the lab up

```bash
./lab/deploy.sh up
```

This calls `containerlab deploy -t lab/topology.clab.yml`. It creates a Docker
network and starts each node. First run pulls images; subsequent runs are
fast.

Verify:

```bash
sudo containerlab inspect -t lab/topology.clab.yml
```

You should see all nodes in `running` state with IPs on the `clab` management
network.

## Running playbooks against the lab

The lab uses the static inventory at `ansible/inventory/lab/hosts.yml`, which
maps node names to the connection methods each container expects. Run any
playbook with:

```bash
ansible-playbook -i ansible/inventory/lab/hosts.yml \
  ansible/playbooks/site.yml --check --diff
```

`--check --diff` is the default during development. Drop `--check` to apply
changes inside the lab (no risk — the lab is ephemeral).

## Tearing it down

```bash
./lab/deploy.sh down
```

Containerlab removes the containers and the management network. Leftover
`clab-*` directories are cleaned up.

## CI integration

The `.github/workflows/lab.yml` workflow runs the lab on a manual
`workflow_dispatch` trigger. It is **not** part of the default PR pipeline —
spinning up SR Linux takes ~60 s per node and you don't want it on every push.
The lint and Molecule workflows do run on every PR.

## Limits and trade-offs

- **FortiGate roles are not exercised in the lab.** Their Molecule scenarios
  test only that the role syntax-checks against a FortiGate-shaped fake host.
  Real validation requires the FortiGate-VM eval image on a host with KVM.
- **Cisco IOS roles** are exercised against Nokia SR Linux at the
  "vendor-agnostic interface" level — meaning the role's variables and
  dispatcher logic are tested, but the IOS-specific implementation file is not
  executed against a real IOS device. End-to-end IOS validation requires
  CML / IOL-XE on a self-hosted runner.
- **Windows roles** require a `windows-latest` GitHub runner; they are tested
  in a separate workflow.

See [testing.md](testing.md) for the full testing pyramid and how each tool
fits in.
