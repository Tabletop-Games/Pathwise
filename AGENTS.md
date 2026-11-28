# Pathwise agent guide

This is the single canonical instruction file for every coding agent (Kiro, Codex, Antigravity and others). Tool-specific files only point here.

Pathwise is a pre-release, Android-only, local-first Flutter route-puzzle game by Tabletop Games. Draw one path from checkpoint 1 through every tile, visiting the numbers in order.

## Product policy

- **Android only.** Do not build, test, investigate or modify iOS. Do not add iOS CI jobs or iOS code paths. The `ios/` directory is dormant scaffolding excluded from analysis; see [docs/development.md](docs/development.md#android-only).
- **Offline-capable.** Campaign, Daily Challenge, Time Attack, tutorials and every coin purchase work without a network. Only ads, Google Play Billing and Play Games (sign-in and cloud save) need connectivity, and they fail gracefully. `ConnectivityService` is the only place that decides whether the device is online; screens never probe the network. Gameplay never waits for a network feature.
- **No hosted backend.** Do not add Cloud Run, Firestore, custom APIs or backend-issued identities. Progress syncs through Google Play Games Saved Games ([docs/cloud-saves.md](docs/cloud-saves.md)). The client is not tamper-proof and the docs say so.
- **Pre-release: no historical compatibility.** There are no existing players. Do not write or keep migrations, legacy readers, old identifiers, old generation versions or compensation for earlier development builds. Keep one current save schema and one current cloud envelope. Current-format validation, corruption detection, transaction integrity and real purchase restoration stay.
- **Current product facts live in [docs/](docs/)**: [gameplay](docs/gameplay.md), [economy](docs/economy.md), [design system](docs/design-system.md), [architecture](docs/architecture.md), [monetization](docs/monetization.md), [cloud saves](docs/cloud-saves.md), [security](docs/security.md), [Play Games](docs/play-games.md), [development](docs/development.md), [release](docs/release.md), [Play Console setup](docs/play-console-setup.md). Read the one you are changing before changing it. Do not infer product rules from an old test.
- Do not invent economic rates or gameplay rules. Economy values live in `lib/model/economy.dart` and `lib/model/progression.dart`; star thresholds live in `lib/logic/star_rating.dart`.

## Design work

Before any substantial UI, UX, theme, artwork, animation or screen work, load the canonical skill [.agents/skills/pathwise-design/SKILL.md](.agents/skills/pathwise-design/SKILL.md) and the references it names. Codex and Antigravity discover `.agents/skills/` directly. Kiro discovers it through the adapter in `.kiro/skills/pathwise-design/`. Do not copy the skill into other files.

## Architecture rules

- Dependency direction: views → ViewModels and `AppModel` → pure domain; services and storage sit beside `AppModel`. `lib/logic`, `lib/cloud` and `lib/model` (except `app_model.dart` and `app_themes.dart`) must not import `lib/views`, `lib/ui` or `AppModel`. `test/architecture_boundaries_test.dart` enforces this.
- Pure rules live in `lib/logic`, `lib/model` and `lib/cloud` and are unit-tested. Presentation coordination lives in `lib/viewmodels` (no `BuildContext`, no widgets). `AppModel` owns shared player state and persistence. Widgets stay declarative.
- A reward, spend or purchase uses a stable ledger ID, mutates state and persists in one `flush()`, and rolls back if the write fails. Never grant before the save succeeds.
- Keep puzzle seeds, checkpoint order and route semantics deterministic. Use named, seeded fixtures and fake clocks in tests.
- Keep pointer-only rendering inside the board's pointer layer.
- Keep monetization flags off by default. Use the Play internal track and AdMob test units before live services. Never commit signing keys, service-account credentials or purchase tokens.
- Preserve R8 optimisation. Add a keep rule only for a diagnosed problem, scoped to the class or member.
- Keep the application IDs `com.shenmareparas.pathwise` (release) and `com.shenmareparas.pathwise.debug`.
- Keep GPL-3.0 notices, the upstream Chess attribution and the Bricolage Grotesque OFL notice.

## Verification

Run before every commit, and expect CI to run the same:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
dart run tool/economy_simulation.dart
dart run tool/validate_catalogue.dart   # slow; CI runs it
```

Release-affecting changes also need the Android debug APK, the minified release APK and AAB, and the R8 checks in [docs/release.md](docs/release.md). Analyzer infos fail CI. Do not use `continue-on-error` for a correctness check. Do not claim a build, test or emulator run that did not happen.

## Keep the repository in step with the code

A change is not finished until the repository matches it. When you add, change or remove a feature:

1. Update the relevant document in `docs/`.
2. Update this file and the design skill if a rule or reusable principle changed.
3. Update or rewrite the affected tests. Delete tests of removed behaviour. Do not weaken a test to make it pass; a failing test that finds a real defect stays.
4. Delete superseded code, orphaned assets, unused dependencies and unused tooling.
5. Delete completed or superseded plans and specifications. Do not leave finished `.kiro/specs`, audit reports or implementation notes behind.
6. Check that Markdown links resolve and that no document contradicts the code.

Do not add a new audit report or historical document for each task. History belongs in Git, commit messages and pull requests. Do not create `archive`, `old`, `backup` or `deprecated` directories.

## Git

- Commit as **Aman Sanoj** `<72658023+amansanoj@users.noreply.github.com>`. Set it locally (`git config --local user.name`, `user.email`) and check `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT`. No agent identities, bot addresses or co-author trailers.
- Work on a branch, open a pull request into `main`, and never force-push or rewrite shared history. Do not merge your own pull request unless asked.
- Never commit credentials. CI scans tracked files for private keys and tokens.
