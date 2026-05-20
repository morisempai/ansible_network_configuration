"""Post-deploy assertions for network devices (placeholder).

Network devices are not POSIX hosts, so the standard testinfra `host`
fixtures (package/file/service) do not apply. The intended approach is one
of:

  * drive `show` commands through pyATS / Genie structured parsers, or
  * query the device API (NETCONF / gNMI / FortiOS REST) directly and assert
    on the returned data.

This module is a stub so the test suite collects cleanly; flesh it out once
the role implementations produce real device state.
"""
import pytest

pytestmark = pytest.mark.network


@pytest.mark.skip(reason="network device assertions not yet implemented")
def test_vlan_database_matches_intent():
    """Every VLAN from group_vars/network.yml must exist on the device."""
    raise NotImplementedError


@pytest.mark.skip(reason="network device assertions not yet implemented")
def test_storage_vlan_has_no_l3_interface():
    """Invariant: VLAN 30 (storage) must never have an SVI / L3 interface."""
    raise NotImplementedError
