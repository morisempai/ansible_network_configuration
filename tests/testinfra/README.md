# testinfra — post-deploy state verification

[pytest-testinfra](https://testinfra.readthedocs.io/) asserts the *real* state
of hosts after a deploy, using checks that are independent of Ansible's own
change reporting. Ansible saying `ok` only means a module did not error;
testinfra confirms the box actually looks the way it should.

## Running

Against the Containerlab lab:

```bash
./lab/deploy.sh up
ansible-playbook -i ansible/inventory/lab/hosts.yml ansible/playbooks/site.yml

pytest tests/testinfra/ -v \
  --hosts='ansible://linux?ansible_inventory=ansible/inventory/lab/hosts.yml'
```

The `ansible://` backend reuses the project inventory, so testinfra targets
exactly the hosts Ansible just configured.

## Layout

| File                         | Scope                                   |
|------------------------------|-----------------------------------------|
| `conftest.py`                | shared fixtures / marker registration   |
| `test_linux_baseline.py`     | Linux host assertions (chrony, sshd)     |
| `test_network_baseline.py`   | network device assertions (placeholder) |

## Status

`test_linux_baseline.py` contains working assertions for the `common` and
`linux_base` roles. `test_network_baseline.py` is a placeholder — network
device checks are best driven through `pyATS`/`Genie` or vendor `show`
parsers, to be wired up once role implementations stabilise.
