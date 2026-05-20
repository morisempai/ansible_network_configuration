<!--
  Thanks for opening a PR! Please fill out the sections below.
  PRs that bypass this template may be asked to rework.
-->

## Summary
<!-- 1–3 sentences. What changed and why. -->

## Scope
- [ ] Role(s) touched: `…`
- [ ] Playbook(s) touched: `…`
- [ ] Inventory / group_vars touched: `…`
- [ ] CI / lab / tooling only

## Testing performed
<!-- Tick everything that applies. Attach output where useful. -->
- [ ] `pre-commit run --all-files` is clean
- [ ] `yamllint .` is clean
- [ ] `ansible-lint ansible/` is clean
- [ ] `molecule test` passes for each touched role
- [ ] `./lab/deploy.sh up` + `ansible-playbook --check --diff` against the lab
- [ ] Manual smoke test on staging (describe below)

## Risk / blast radius
<!-- Which sites? Which device classes? Any deny-by-default policy changes? -->

## Rollback plan
<!-- How to revert if this misbehaves in production. -->

## Linked issue
<!-- Closes #… -->
