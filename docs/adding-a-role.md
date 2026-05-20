# Adding a new role

This repo follows a strict pattern: every role exposes the **same variable
interface** across vendors. The role's `tasks/main.yml` dispatches to a
vendor-specific implementation based on `ansible_network_os`. New roles must
follow this pattern.

## 1. Scaffold

```bash
ROLE=my_new_role
mkdir -p ansible/roles/$ROLE/{tasks,defaults,meta,molecule/default}
touch ansible/roles/$ROLE/{README.md,defaults/main.yml,meta/main.yml,tasks/main.yml}
```

## 2. Dispatcher (`tasks/main.yml`)

Copy this verbatim — every network role in the repo uses it unchanged except
for the role name in the task `name:`. (`common`, `linux_base` and
`windows_ad` vary slightly; see those roles.)

```yaml
---
# Dispatcher. Maps ansible_network_os -> per-vendor task file, falling back to
# ansible_os_family for non-network hosts, then to linux.yml. Missing
# implementations are silently skipped (errors='ignore').
- name: "my_new_role | include vendor task file"
  ansible.builtin.include_tasks: "{{ _vendor_task_file }}"
  vars:
    _vendor_map:
      cisco.ios.ios: cisco_ios.yml
      cisco.nxos.nxos: cisco_nxos.yml
      nokia.srlinux.srlinux: srlinux.yml
      frr.frr.frr: frr.yml
      fortinet.fortios.fortios: fortios.yml
    _candidates:
      - "{{ _vendor_map[ansible_network_os | default('none')] | default('') }}"
      - "{{ ansible_os_family | default('') | lower }}.yml"
      - "linux.yml"
    _vendor_task_file: >-
      {{ lookup('ansible.builtin.first_found',
                _candidates, errors='ignore',
                paths=[role_path + '/tasks']) }}
  when: _vendor_task_file | length > 0
```

The dispatcher checks `ansible_network_os` first (set for network devices),
then `ansible_os_family` (set for Linux/Windows servers), then falls back to
`linux.yml`. Add the per-vendor task files your role actually targets:

| File              | Device class                       |
|-------------------|------------------------------------|
| `cisco_ios.yml`   | Cisco IOS / IOS-XE                 |
| `cisco_nxos.yml`  | Cisco NX-OS / MDS                  |
| `srlinux.yml`     | Nokia SR Linux                     |
| `frr.yml`         | FRRouting                          |
| `fortios.yml`     | FortiGate                          |
| `linux.yml`       | generic Linux                      |
| `windows.yml`     | Windows Server / AD                |

Only create the files your role targets. `first_found` with `errors='ignore'`
silently skips missing candidates, and the `when:` guard makes the whole
include a clean no-op when no implementation exists for the host's vendor.

## 3. Variable interface (`defaults/main.yml`)

Define the role's input variables here, with sensible defaults. The
**same** variables drive every vendor implementation:

```yaml
---
# Example: interfaces role
my_new_role_interfaces: []
# - name: Ethernet1/1
#   description: link to core
#   enabled: true
#   mtu: 9100
```

Document every variable in the role's `README.md`.

## 4. Per-vendor implementation

Each vendor file consumes the same variables but speaks the vendor's modules:

```yaml
# tasks/cisco_ios.yml
- name: "my_new_role | cisco_ios | configure interfaces"
  cisco.ios.ios_interfaces:
    config: "{{ my_new_role_interfaces }}"
    state: merged
```

```yaml
# tasks/srlinux.yml
- name: "my_new_role | srlinux | configure interfaces"
  nokia.srlinux.config:
    update:
      - path: /interface[name={{ item.name }}]
        value:
          admin-state: "{{ 'enable' if item.enabled else 'disable' }}"
          description: "{{ item.description | default(omit) }}"
          mtu: "{{ item.mtu | default(omit) }}"
  loop: "{{ my_new_role_interfaces }}"
```

## 5. Molecule scenario

```yaml
# molecule/default/molecule.yml
---
dependency:
  name: galaxy
driver:
  name: default
platforms:
  - name: srl-test
    groups: [network, srlinux]
  - name: linux-test
    groups: [linux]
provisioner:
  name: ansible
  inventory:
    host_vars:
      srl-test:
        ansible_network_os: nokia.srlinux.srlinux
verifier:
  name: ansible
```

```yaml
# molecule/default/converge.yml
---
- name: Converge
  hosts: all
  gather_facts: false
  roles:
    - role: my_new_role
```

```yaml
# molecule/default/verify.yml
---
- name: Verify
  hosts: all
  gather_facts: false
  tasks:
    - name: Assert something true about the resulting state
      ansible.builtin.assert:
        that:
          - true
```

Run it:

```bash
cd ansible/roles/my_new_role
molecule test
```

## 6. README

Every role needs a `README.md` with: purpose, supported device classes,
variable reference, example usage, known limitations.

## 7. Open a PR

CI will run lint and Molecule against the role automatically.
