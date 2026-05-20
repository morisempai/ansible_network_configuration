# tests/

Testing that sits *outside* the per-role Molecule scenarios. See
[../docs/testing.md](../docs/testing.md) for how these fit the overall
strategy.

| Directory    | Tool             | When it runs                | What it checks                       |
|--------------|------------------|-----------------------------|--------------------------------------|
| `batfish/`   | Batfish          | pre-deploy (offline)        | config correctness & policy invariants |
| `testinfra/` | pytest-testinfra | post-deploy (against hosts) | real device/server state             |

## Quick start

```bash
pip install -r ansible/requirements.txt        # base tooling
pip install pybatfish pytest-testinfra          # optional extras

# Pre-deploy: analyse rendered configs as data
python tests/batfish/run_batfish.py path/to/configs/

# Post-deploy: assert real state of converged hosts
pytest tests/testinfra/ --hosts='ansible://all?ansible_inventory=ansible/inventory/lab/hosts.yml'
```

## Why both

- **Molecule** proves a *role* does what it says on an isolated host.
- **Batfish** proves the *whole rendered config set* is internally consistent
  and does not violate design invariants (VLAN 30 non-routed, VLAN 50 no
  egress, deny-by-default) — before anything is pushed.
- **testinfra** proves the *live estate* matches intent after a deploy, using
  assertions independent of Ansible's own change reporting.
