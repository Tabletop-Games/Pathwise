# Unified Store requirements

- Provide one themed Store with fixed category navigation for Themes, Tips, Coins and Upgrades, supporting direct entry and preserving category position.
- Replace Wallet and transaction-history UI navigation with the Coins category while retaining economy records and recovery data.
- Present themes in a three-column grid using a shared, valid partial Level 1 board and independent candidate palettes; preview is isolated and never purchases or equips.
- Offer Classic and 19 independently priced, original vector tips. Classic is free; each paid tip initially costs 100 coins. Preview, purchase and Apply are distinct actions. Existing theme entitlements do not grant tips.
- Render tips with cardinal orientation derived from accepted logical route movements, excluding portal jumps, including backtracking and forced slides. Preserve existing path validation and rejection feedback.
- Resolve vector colors from active theme roles with contrast, use lazy grids and accessible controls, and support large text and safe areas.
- Atomically deduct the existing ledger balance and persist ownership with idempotent operations. Persist equipped tip, safely default old or invalid state to Classic, and synchronize across devices through the existing Play Games Saved Games architecture.
- Use existing ad/billing services and products. Automatic rewarded-coin offers require both five new levels and 15 minutes, existing readiness/eligibility, and suppression for active gameplay, modal conflicts and ad-free entitlements. Rewards are granted only through the existing earned-reward callback and share existing limits.
- Preserve existing gameplay, balances, entitlements, reward records, online requirements, package identities and signing. Do not introduce another backend or infrastructure.
