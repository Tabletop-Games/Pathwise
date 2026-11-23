# Project context

Pathwise is a wall-free Android route puzzle using Flutter and Provider. The code adapts GPL-3.0 architecture from [shenmareparas/Chess](https://github.com/shenmareparas/Chess). Preserve attribution and the Bricolage Grotesque font notice.

- [Architecture and persistence](../docs/architecture.md)
- [Gameplay invariants, solver and interaction](../docs/gameplay.md)
- [Hint tank](../docs/hints.md), [economy](../docs/economy.md), [research](../docs/research.md), [boosts](../docs/boosts.md) and [crates](../docs/crates.md)
- [Monetization](../docs/monetization.md), [backend](../docs/backend.md), [security](../docs/security.md) and [Play Games](../docs/play-games.md)
- [Publisher setup](../setup.md), [release procedure](../docs/release.md) and [performance](../docs/performance.md)

Treat puzzle IDs, checkpoint order, accepted route semantics and canonical generation output as compatibility contracts. Keep the 3/3 tank and three-standard-hint cap independent. Only a separate verified ad receipt can authorize each further hint. Entitlements and progression effects must never bypass this.

Extension priorities are Play device verification, gesture and large-font visual testing on hardware, ranked score validation, cloud-backed paid-currency recovery and refund reconciliation. Preserve Flutter plugin registration and explicit code and resource shrinking.
