"""Post-deploy assertions for Linux hosts.

Covers state produced by the `common` and `linux_base` roles. These run
against live hosts via the testinfra Ansible backend.
"""
import pytest

pytestmark = pytest.mark.linux


def test_chrony_installed(host):
    """common role: chrony must be installed for time sync."""
    assert host.package("chrony").is_installed


def test_chrony_config_has_ntp_servers(host):
    """common role: chrony.conf must list the management-VLAN NTP servers."""
    conf = host.file("/etc/chrony/chrony.conf")
    assert conf.exists
    assert conf.contains("server 10.0.10.10")


def test_resolv_conf_has_dns(host):
    """common role: resolv.conf must point at the management-VLAN resolvers."""
    resolv = host.file("/etc/resolv.conf")
    assert resolv.exists
    assert resolv.contains("nameserver 10.0.10.20")


def test_sshd_root_login_disabled(host):
    """linux_base role: root SSH login must be disabled."""
    sshd = host.file("/etc/ssh/sshd_config")
    assert sshd.contains("PermitRootLogin no")


def test_sshd_password_auth_disabled(host):
    """linux_base role: SSH password authentication must be disabled."""
    sshd = host.file("/etc/ssh/sshd_config")
    assert sshd.contains("PasswordAuthentication no")


def test_sudoers_dropin_present(host):
    """linux_base role: the managed sudoers drop-in must exist and be 0440."""
    dropin = host.file("/etc/sudoers.d/10-ansible-groups")
    assert dropin.exists
    assert oct(dropin.mode) == "0o440"
