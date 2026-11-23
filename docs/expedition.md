# Infinite Expedition

## Journey and replay

Every trail contains ten stages, four field marks, and a two-mark qualification target. Solve all ten stages and earn any two marks. Qualification opens the next numerical trail and offers a Continue action from the result. A missed mark leaves the puzzle and run playable. Leaving or closing the app preserves the current board and run. Explicit abandonment records the depth reached.

Browse nearby unlocked trails or enter any unlocked trail number directly. Replays generate another seeded variant and can improve deepest stage, marks, or fastest qualifying time. The first three trail names, legacy stage conditions, and twelve repeating board variants are unchanged. The procedural trails use the full run serial. Trail number, run serial and stage identify an attempt, including its hint use. New content is generated on demand even offline.

## Generation and difficulty

The original board generation namespace is retained for Foothills, Ridgeline and Summit. Later trails hash a versioned numeric index into a deterministic biome, name and objective layout. Each board hashes the trail number, run serial and stage. Two independently solver-certified layouts are compared by the squared gaps between ordered checkpoints, capped at ten moves per gap for scoring. This favors longer deductions within the search budget. Each candidate retains extra checkpoints when required to prove uniqueness. No generated board is stored as an asset or in a save.

The bands are introductory (1–3), exploration (4–10), developing mastery (11–25), advanced (26–50), expert (51–100), and sustained mastery (101 onward). Grids stay between 4×4 and 7×7. Difficulty changes through clue density, longer deductions and procedural objectives, then stays within the last band. The mode fits ordinary supported positive integer indices. Generation and navigation are tested through 9,007,199,254,740,991. There is no game-defined endpoint.

The first three trails keep their original marks. A procedural trail puts one objective in each of four nonoverlapping stage windows. The trail seed rotates the four objectives and selects their positions. The conditions are hint-free, no Clear, no Undo, and no hints or Clear. A normal unassisted solution can earn every mark. Timing has no effect on mark eligibility. Undo, Clear, ordinary backtracking and hints remain available. Standard and rewarded hints use the shared three-slot tank rules. All records are local.

## Rewards and milestones

Introductory trails pay their existing 12 coins at stages 3 and 6 and 36 on first qualification. Later trails pay 4 at stages 3 and 6 and `20 + min(floor(trail / 10), 12)` for first qualification. Four marks on that first qualification add four coins. Prior milestones stay claimed through abandonment and restart. Coin boosts do not multiply these rewards. The Field Guide achievement still uses the normal achievement and Research rules.

Trail 3 earns Basin Gold. Trails 10, 25, 50 and 100 pay 24, 30, 42 and 60 milestone coins. Trail 25 also earns Copper Sky and trail 100 earns High Pass. From trail 125 onward every 25th trail pays 24 coins, with each multiple of 100 paying 60 instead. All Themes Forever can also unlock the cosmetics. The existing supply crate and ad rules apply.

The first 10,000 trails pay 412,552 coins through qualification and milestone awards under normal play, or 452,540 with four marks on every first qualification. That is 4.13–4.53 coins per solved stage, compared with 12 for a first Level clear before research. The simulation excludes crates, general achievements, earned ads and all other modes. At sustained mastery a normal trail yields 40 coins and a perfect one yields 44 before milestone awards. Replay payout for earlier trails is zero.

## Persistence and scaling

Schema 7 keeps the current frontier, the frontier's cleared, hint-free and rewarded stage bitsets, and the historical hint-free total. Past qualification is implicit in the frontier and reward identities use stable trail and milestone keys. Frontier changes and wallet credits commit in one application snapshot. Only 32 recent Expedition, Wheel and Field Notes credit rows and 12 run summaries stay in the snapshot. Earlier Expedition currency stays in the wallet's archived credit total. Level, Daily, and Time Attack persistence is unchanged. Earlier Endless completions still count toward lifetime totals.

Each trail's best depth, most marks and fastest qualifying run fit in a ten-byte record. Android stores them in independently addressed 2,560-byte pages with up to 256 records each. A trail lookup reads one page. The app caches at most 12 records and loads no page at startup. At 100,000 consecutive trails this occupies about 1.0 MB of record payload on disk. Index allocation does not depend on the largest trail number. Updates merge bests and replace the page atomically. Bests can survive an interruption before the main snapshot commits. Retrying cannot duplicate progression or currency. Replays improve each trail's indexed records. Lifetime Expedition board totals count each frontier stage once and do not increase on paid-out trail replays.

Old saves restore the first three trails, outstanding attempts, claims and records. A Summit qualification resumes at trail 4. The active run uses its preserved stage state and seed. As with other local data, clearing app storage removes Expedition records.

## Verification

Tests cover deterministic high-index and randomized generation, unique solutions, fair marks, indexed record reload and storage size, old Summit migration, advancement after trail 100,000, immediate continuation, offline resumption, replay idempotency, balance compaction, milestone recurrence and large-number UI navigation.

The Linux host benchmark generated 30 boards from three variants per sampled trail. Trail 10 measured 2.46 ms median and 14.51 ms p95. Trail 100,000 measured 8.52 ms median and 19.56 ms p95. These timings exclude isolate startup and Android rendering.
