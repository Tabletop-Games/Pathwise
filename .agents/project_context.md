# Project context

Pathwise is an online-first Android and iOS route puzzle using Flutter and Provider, with a Cloud Run and Firestore backend that is authoritative for identity, the economy and progression ([online architecture](../docs/online-architecture.md), [deployment](../docs/deployment.md)). The code adapts GPL-3.0 architecture from [shenmareparas/Chess](https://github.com/shenmareparas/Chess). Preserve attribution and the Bricolage Grotesque font notice.

- [Architecture and persistence](../docs/architecture.md)
- [Gameplay invariants, solver and interaction](../docs/gameplay.md) and [game modes](../docs/game-modes.md)
- [Hint wallet](../docs/hints.md), [economy](../docs/economy.md), [research](../docs/research.md), [boosts](../docs/boosts.md) and [crates](../docs/crates.md)
- [Monetization](../docs/monetization.md), [backend](../docs/backend.md), [security](../docs/security.md) and [Play Games](../docs/play-games.md)
- [Text-only result sharing](../docs/social-sharing.md) and [native Play Games achievement synchronization](../docs/google-play-achievements.md)
- [Publisher setup](../setup.md), [release procedure](../docs/release.md) and [performance](../docs/performance.md)

Treat puzzle IDs, checkpoint order, accepted route semantics and canonical generation output as compatibility contracts; `backend/engine` must generate the same boards, so change both together. Keep prices and rewards in `backend/economy-config.mjs` and mirror them in `lib/model` (the parity test fails otherwise). Never grant rewards on the client. Maintain shared movement rules for the solver, gesture controller, restore, hint routing and server validation. Preserve generated legacy boards when extending Levels.

Extension priorities are deploying the backend, Play device verification, Play Integrity on the client, gesture and large-font visual testing on hardware, and an App Store server verifier. Preserve Flutter plugin registration and explicit code and resource shrinking.

Android keeps its black native launch screen visible while saved state and the clock load, then renders the home screen with the saved theme. Settings offers an optional Google Play update check using in_app_update_flutter. Play-distributed builds and an eligible newer release are needed to verify the update flow.
