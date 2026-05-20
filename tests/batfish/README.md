# Batfish — pre-deploy config analysis

[Batfish](https://www.batfish.org/) parses network configurations as data and
answers questions about them *without touching a device*. It is the guard
that catches "did I just blackhole VLAN 50" before the change ships.

## How it works here

1. A playbook run with `--check` (or a dedicated render step) produces the
   candidate device configs into a snapshot directory.
2. `run_batfish.py` loads that snapshot into a Batfish service and runs:
   - built-in sanity questions (undefined references, unused structures,
     duplicate route-maps, …);
   - project-specific invariant checks derived from
     `docs/architecture-brief.md`.
3. Any violation exits non-zero, failing the CI job.

## Running Batfish

Batfish runs as a service container:

```bash
docker run --name batfish -d -p 9997:9997 -p 9996:9996 \
  batfish/allinone
python tests/batfish/run_batfish.py ./snapshot/
```

## Invariants checked (see run_batfish.py)

| Invariant                                   | Source                       |
|---------------------------------------------|------------------------------|
| VLAN 30 (storage) has no L3 interface       | architecture-brief, topology |
| VLAN 50 (critical infra) has no egress path | architecture-brief, security |
| Inter-VLAN default action is `deny`         | architecture-brief, security |

## Status

`run_batfish.py` is a working skeleton: the built-in questions run today; the
invariant checks are stubbed with `TODO` markers and should be fleshed out as
the role implementations produce real configs.
