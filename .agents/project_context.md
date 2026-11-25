# Project context

Pathwise is a local-first, offline-capable Android route puzzle using Flutter and Provider. The code adapts GPL-3.0 architecture from [shenmareparas/Chess](https://github.com/shenmareparas/Chess). Preserve attribution and the Bricolage Grotesque font notice.

- [Architecture and persistence](../docs/architecture.md)
- [Internet requirement and connection handling](../docs/connectivity.md)
- [Cloud saves, sync rules and limits](../docs/cloud-saves.md)
- [Gameplay invariants, solver and interaction](../docs/gameplay.md) and [game modes](../docs/game-modes.md)
- [Hint wallet](../docs/hints.md), [economy](../docs/economy.md), [research](../docs/research.md), [boosts](../docs/boosts.md) and [crates](../docs/crates.md)
- [Monetization](../docs/monetization.md), [security](../docs/security.md) and [Play Games](../docs/play-games.md)
- [Text-only result sharing](../docs/social-sharing.md) and [native Play Games achievement synchronization](../docs/google-play-achievements.md)
- [Setup](../setup.md), [Play Console and AdMob guide](../docs/play-console-setup.md), [release procedure](../docs/release.md) and [performance](../docs/performance.md)

Treat puzzle IDs, checkpoint order, accepted route semantics and canonical generation output as compatibility contracts. Keep hint grants and spending in the persistent wallet. Maintain shared movement rules for the solver, gesture controller, restore, and hint routing. Preserve generated legacy boards when extending Levels.

Pathwise is Android-only (see [Android-only policy](../docs/android-only.md)). Extension priorities are Play device verification of Saved Games and billing on configured accounts, gesture and large-font visual testing on hardware, and the Play Integrity client path if a verifier ever exists.

Android keeps its black native launch screen visible while saved state and the clock load, then renders the home screen with the saved theme. Settings offers an optional Google Play update check using in_app_update_flutter. Play-distributed builds and an eligible newer release are needed to verify the update flow.
