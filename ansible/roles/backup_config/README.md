# backup_config

Pulls the running configuration from every network device and writes it to a
timestamped file. Runs **first** in `site.yml` so there is always a
known-good config to roll back to before any change is applied.

## Supported device classes

Cisco IOS, Nokia SR Linux, FRR, FortiGate.

## Variables

| Variable                  | Type | Purpose                                  |
|---------------------------|------|------------------------------------------|
| `backup_config_dir`       | str  | Local directory for backups              |
| `backup_config_git_push`  | bool | Commit + push backups to a git repo      |

## Example

```yaml
- hosts: network
  roles:
    - role: backup_config
```

## Output

```
{{ backup_config_dir }}/<hostname>/<hostname>-YYYYmmdd-HHMMSS.cfg
```

## Known limitations

Git push is a stub: the role writes files locally; wiring it to the dedicated
backup repository is tracked in a follow-up PR.
