# Testing Strategy

A layered approach. Each layer is cheaper and broader than the next; the
expensive layers run less often.

```
        +-------------------------+
        |   Production (AWX)      |   manual MR approval
        +-------------------------+
        |   Staging (real gear)   |   nightly + pre-release
        +-------------------------+
        |   Lab integration       |   on-demand (workflow_dispatch)
        +-------------------------+
        |   Molecule scenarios    |   every PR (matrix per role)
        +-------------------------+
        |   Dry-run --check       |   every PR
        +-------------------------+
        |   Static lint + syntax  |   every push / pre-commit
        +-------------------------+
```

## Layer 1 — Static lint and syntax (free, fast, mandatory)

Pre-commit hooks (also run in CI):

- **`yamllint`** — formatting and indentation.
- **`ansible-lint`** — Ansible idioms, deprecations, security.
- **`shellcheck`** — every `.sh` script in `lab/`.
- **`ansible-playbook --syntax-check`** — every playbook in `ansible/playbooks/`.

Install once:

```bash
pip install -r ansible/requirements.txt
pre-commit install
```

## Layer 2 — Dry-run with `--check --diff`

Every PR runs:

```bash
ansible-playbook -i lab/inventory.yml ansible/playbooks/site.yml --check --diff
```

Caveats:

- The classic `*_config` modules (e.g. `cisco.ios.ios_config`) do not honour
  `--check` cleanly. The roles in this repo prefer **resource modules**
  (`cisco.ios.ios_interfaces`, `fortinet.fortios.fortios_*`) which support
  check + diff correctly.
- Resource modules also produce structured `diff` output suitable for posting
  on the PR.

## Layer 3 — Molecule (role-level isolation)

Every role has a `molecule/default/` scenario:

- `molecule.yml` — driver + platform definition (Containerlab, Docker, or
  delegated).
- `converge.yml` — playbook that applies the role with a representative set of
  variables.
- `verify.yml` — assertions about the resulting device state (run after
  converge).

```bash
cd ansible/roles/<role>
molecule test     # full lifecycle: create → converge → idempotence → verify → destroy
```

The `idempotence` step is the critical one: the role must report
`changed=0` on a second consecutive run.

## Layer 4 — Lab integration

A Containerlab topology that boots a miniature HQ + R1 + R2 in containers and
runs `site.yml` end-to-end. See [lab.md](lab.md). Triggered manually via
`workflow_dispatch` or locally with `./lab/deploy.sh up`.

## Layer 5 — Staging

Real (or partial) hardware: a FortiGate VM, a real C9200 if available, a Linux
VM for AD. Runs nightly and on every release candidate tag. Not part of this
repo — pipeline lives in AWX.

## Layer 6 — Production

AWX-triggered, manual approval gate on the MR. The runbook is identical to
staging; the inventory points at production NetBox.

## Other tooling worth adding (in `tests/`)

- **Batfish** — analyses candidate configs as data and flags reachability /
  policy violations before they reach a device. Excellent for catching
  "did I just blackhole VLAN 50". Skeleton at `tests/batfish/`.
- **pytest-testinfra** — assertions over real device state after apply
  (interface up, ACL hit-count > 0, BGP neighbour established). Skeleton at
  `tests/testinfra/`.
- **SuzieQ** — snapshots network state. Run before and after a change to diff
  routing tables, MAC tables, LLDP neighbours.
- **pyATS / Genie (Cisco)** — structured parsers for `show` output; very strong
  if your estate is Cisco-heavy. Worth wiring up once the IOS roles solidify.

## Backup before change (always)

The `backup_config` role pulls `show running-config` (or the vendor
equivalent) from every network device to a git-tracked backup repository
**before** any other playbook applies. This gives a one-command rollback and
an audit trail independent of AWX.

## Per-class trade-offs

| Device class | Lint | Dry-run | Molecule | Lab | Staging |
|--------------|:----:|:-------:|:--------:|:---:|:-------:|
| Cisco IOS    | ✅   | ✅      | ✅ (against SR Linux as proxy) | partial | ✅ |
| Nokia SR Linux | ✅ | ✅      | ✅       | ✅  | n/a    |
| FRR          | ✅   | ✅      | ✅       | ✅  | n/a    |
| FortiGate    | ✅   | ⚠️ httpapi mocked | ⚠️ syntax only | ❌ | ✅ |
| Linux        | ✅   | ✅      | ✅       | ✅  | ✅     |
| Windows      | ✅   | ✅      | ⚠️ separate runner | ❌ | ✅ |
