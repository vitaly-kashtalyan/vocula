## What changed, and why

<!-- The why matters more than the what — the diff already says what. -->

## How it was verified

<!-- Name what you RAN, not what you believe. "Measured X at N" beats "should
     work". If something could not be checked here — hardware, a permission, a
     language nobody here reads — say so plainly rather than leaving it blank. -->

- [ ] `swift test`
- [ ] `./scripts/check-purity.sh`
- [ ] `./scripts/check-localization.sh`
- [ ] `xcodebuild test -project App/Vocula.xcodeproj -scheme Vocula -only-testing:VoculaAppTests`
- [ ] `cd App && xcodegen generate` (needed after adding, renaming or removing a file under `App/Vocula/`)

## What this made untrue

<!-- Which documented sentences in this repository the change just falsified, and where they are fixed — in THIS pull request,
     not a follow-up. Numbers get re-measured, never carried over. "Nothing" is a
     valid answer; leaving this empty is not. -->

---

<sub>External pull requests are not accepted — a merged patch leaves its author's copyright in the tree. See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md); bug reports and measurements are genuinely wanted.</sub>
