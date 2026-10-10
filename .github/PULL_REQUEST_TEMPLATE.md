## Summary

<!-- What changed and why. Link the related issue. -->

## Checklist

- [ ] CI job `test` is green (`./scripts/test.sh --all` + `./scripts/build-app.sh` on `macos-26`)
- [ ] User-facing copy follows `docs/brand/messaging.md` (Practice, Reference practice, Words, Listen & Repeat, Speak Along)
- [ ] Website: `node scripts/check-website.mjs` and `node scripts/build-website.mjs` when `website/` changes (not part of CI). A website-only pull request does not need Peekaboo or `./scripts/render-previews.sh`
- [ ] App UI changes: live Peekaboo on a Mac after green CI, using `docs/PEEKABOO.md` (not an Actions job)
- [ ] App layout changes: `./scripts/render-previews.sh` when a Mac can run it. Say so when it was not run
- [ ] No secrets or personal recordings. UI reference stays in `docs/screenshots/`; synthetic proofs stay in `build/previews`

## Soft gate

GitHub Free private repos have no required status checks. Still wait for green `test` before merge, and before Peekaboo.
