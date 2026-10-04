## Summary

<!-- What changed and why. Link the related issue. -->

## Checklist

- [ ] CI job `test` is green (`./scripts/test.sh --all` + `./scripts/build-app.sh` on `macos-26`)
- [ ] User-facing copy follows `docs/brand/messaging.md` (Practice, Reference practice, Words, Listen & Repeat, Speak Along)
- [ ] Website copy: `node scripts/check-website.mjs` (not part of CI)
- [ ] UI changes: live Peekaboo on a Mac after green CI, using `docs/PEEKABOO.md` (not an Actions job)
- [ ] Layout changes: `./scripts/render-previews.sh` when a Mac can run it. Say so when it was not run
- [ ] No secrets or personal recordings. UI reference stays in `docs/screenshots/`; synthetic proofs stay in `build/previews`

## Soft gate

GitHub Free private repos have no required status checks. Still wait for green `test` before merge, and before Peekaboo.
