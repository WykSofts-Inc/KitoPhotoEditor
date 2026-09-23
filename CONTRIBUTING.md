# Contributing to KitoPhotoEditor

Thanks for considering a contribution — Kito is open source and welcomes
issues and pull requests from anyone.

## Governance

- **Anyone can open an issue or a pull request.**
- **Only the maintainer ([wyksoftsinc.com](https://wyksoftsinc.com), repo
  owner Wycliff) merges pull requests.** This applies even to contributors
  who are granted write access for other reasons (e.g. triage) — merging is
  reserved for the maintainer after review, not delegated.
- Every PR is verified before merge: it must build, its tests must pass, and
  it must follow the engineering standards linked below. A PR that looks
  right but hasn't been checked against those isn't merged on the strength
  of looking right.

## Before you start

**Open an issue first** for anything beyond a trivial fix (typo, obviously
broken test) — a bug report, a proposed feature, or a design change. This
avoids a PR landing that conflicts with a direction already decided, or
duplicates work in progress. Trivial fixes can go straight to a PR.

## Workflow

1. Fork the repo.
2. Create a branch off `main` (`git checkout -b fix/short-description`).
3. Make your change. Follow
   [KitoPhotoEditor's engineering standards](https://github.com/WykSofts-Inc/KitoPhotoEditor/blob/main/docs/ENGINEERING_STANDARDS.md) —
   no `fatalError()`/`try!`/force-unwraps in public code, MVVM (state in an
   `@Observable` ViewModel, views are a pure function of it), every value
   read from `@Environment(\.kitoTheme)` rather than hardcoded.
4. Add or update tests. Run `swift test` locally and make sure it's green.
5. Update the README if you changed or added public API — a new type or
   modifier needs a usage sample, not just a mention.
6. Open a pull request against `main`. Describe **what** changed and **why**
   — link the issue it addresses if there is one.
7. Wait for review. The maintainer may ask for changes before merging —
   that's normal, not a rejection. Please don't merge your own PR even if
   your fork has that permission; leave the merge button to the maintainer.

## Code review checklist (what verification covers)

- [ ] Builds cleanly (`swift build`)
- [ ] Tests pass (`swift test`), and new behavior has new tests
- [ ] No `fatalError()`, `try!`, or unexplained force-unwrap in public code
- [ ] No hardcoded color/spacing/font/radius — reads from the theme
- [ ] Public API changes are documented in the README with a sample
- [ ] A platform-gated feature (e.g. a framework only on some platforms)
      ships its fallback branch in the same PR, not as a follow-up

## Reporting a bug

Open an issue with: what you expected, what happened instead, iOS version
and device (or simulator), and a minimal repro if you can manage one. A
repro is worth far more than a long description.

## Proposing a feature

Open an issue describing the use case before writing code — "I need X to do
Y" is more useful than "please add X," since it lets the maintainer suggest
an approach that fits the rest of the ecosystem before you've built the
wrong shape.

## Code of conduct

Be respectful. Disagreement about a technical approach is fine and expected;
personal attacks, harassment, or bad-faith arguing are not, and will get a
contributor blocked from the repo.

## License

By contributing, you agree your contribution is licensed under this repo's
[MIT License](LICENSE).
