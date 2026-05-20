"""Shared pytest-testinfra configuration.

Run with the Ansible backend so the project inventory is the single source of
host truth, e.g.:

    pytest tests/testinfra/ \\
      --hosts='ansible://linux?ansible_inventory=ansible/inventory/lab/hosts.yml'
"""


def pytest_configure(config):
    """Register custom markers used by the test modules."""
    config.addinivalue_line(
        "markers", "linux: assertions that apply to Linux hosts only"
    )
    config.addinivalue_line(
        "markers", "network: assertions that apply to network devices only"
    )
