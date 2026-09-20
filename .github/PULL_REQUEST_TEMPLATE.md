## Summary

<!-- What changed and why. -->

## Checklist

- [ ] CI job `test` is green (`./scripts/test.sh --all` + `./scripts/build-app.sh` on `macos-26`)
- [ ] UI changes: live Peekaboo on a Mac **after** green CI (not in Actions)
- [ ] Layout / chrome changes: `./scripts/render-previews.sh` when feasible (local or agent, **not** CI)
- [ ] No secrets; no committed QA screenshots (`docs/screenshots/` is fixture layouts only)

## Soft gate

GitHub Free private repos have no required status checks. Still wait for green `test` before merge, and before Peekaboo.
