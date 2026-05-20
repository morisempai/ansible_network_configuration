#!/usr/bin/env python3
"""Pre-deploy config analysis with Batfish.

Loads a snapshot of rendered device configs and runs both Batfish's built-in
sanity questions and the project-specific design invariants documented in
docs/architecture-brief.md.

Usage:
    python tests/batfish/run_batfish.py <snapshot_dir> [--host <batfish_host>]

Exit code is non-zero if any sanity question or invariant check fails, so the
script is safe to use directly as a CI gate.
"""
from __future__ import annotations

import argparse
import sys

try:
    from pybatfish.client.session import Session
except ImportError:  # pragma: no cover - optional dependency
    sys.stderr.write(
        "pybatfish is not installed. Run: pip install pybatfish\n"
    )
    sys.exit(2)


SANITY_QUESTIONS = (
    "undefinedReferences",
    "unusedStructures",
    "referencedStructures",
)


def load_snapshot(snapshot_dir: str, host: str) -> Session:
    """Connect to a Batfish service and initialise the snapshot."""
    bf = Session(host=host)
    bf.set_network("ansnet")
    bf.init_snapshot(snapshot_dir, name="candidate", overwrite=True)
    return bf


def run_sanity(bf: Session) -> int:
    """Run Batfish's built-in sanity questions. Returns a failure count."""
    failures = 0
    for name in SANITY_QUESTIONS:
        question = getattr(bf.q, name)()
        answer = question.answer().frame()
        if not answer.empty:
            failures += len(answer)
            print(f"[FAIL] {name}: {len(answer)} finding(s)")
            print(answer.to_string())
        else:
            print(f"[ OK ] {name}")
    return failures


def check_invariants(bf: Session) -> int:
    """Project-specific design invariants. Returns a failure count.

    TODO: implement once roles render real configs. Sketch:
      * VLAN 30 must not appear in `bf.q.interfaceProperties()` with an IP.
      * VLAN 50 must have no permit path to the internet via
        `bf.q.reachability(...)`.
      * The default inter-VLAN ACL action must be `deny`.
    """
    print("[SKIP] design invariants — not yet implemented (see TODO)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot_dir", help="directory of rendered configs")
    parser.add_argument("--host", default="localhost", help="Batfish host")
    args = parser.parse_args()

    bf = load_snapshot(args.snapshot_dir, args.host)
    failures = run_sanity(bf) + check_invariants(bf)

    if failures:
        print(f"\nBatfish analysis FAILED with {failures} finding(s).")
        return 1
    print("\nBatfish analysis passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
