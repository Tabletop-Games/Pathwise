# Level catalogue evaluation

The production Levels catalogue contains 1,000 deterministic boards generated on the device. Each level seed derives from `pathwise-catalogue-v3` and its level identifier. Generation constructs candidate routes, certifies uniqueness with the bounded solver, and compares the first two certified candidates against a gradually increasing score target. Candidate ranking also favors mechanics for which removing a restriction exposes at least two solutions within a bounded search. Loading remains off the UI isolate. Daily and Time Attack generation remain separate.

The introductory bands use 4×4 boards for levels 1–30, 5×5 for 31–100, 6×6 for 101–300, and 7×7 for 301–1000. Walls first appear at 31, ice at 71, keys and gates at 121, and portals at 201. The first combination is walls and ice at 101. Levels 301 onward cycle through pairs, triples, and all four mechanics. Directional arrows remain supported for existing or custom boards, with their own tutorial, but are not generated in the new catalogue.

The score combines legal decision points and alternatives along the certified route, route turns, logarithmic solver search effort, and the number of interacting mechanic types. It is a selection heuristic, not a measurement of human difficulty. Candidate ranking adds preference for a mechanic proven to rule out alternatives; bounded inconclusive searches and non-unique relaxed boards do not provide a complete measure of mechanic value. Size, clue counts and generator structure also influence the score. No automated score establishes that an individual puzzle is interesting or that the curve is comfortable; human playtesting is still needed.

Run `dart run tool/validate_catalogue.dart` to regenerate the following measurements. A standalone Dart VM run on this workspace validated the first 1,000 levels by generating each twice, certifying uniqueness, playing the solution and each hint through `GameController`, and comparing rotation/reflection-normalized board signatures. It reported zero duplicate signatures and zero validation failures. The full audit took approximately 57 seconds in this environment; this is not a mobile level-load benchmark. Of 970 boards with mechanics, 513 had at least one mechanic proven to eliminate an alternative solution by the bounded relaxation check. The remaining boards are not proven uninteresting, but require further design review.

| Levels | Minimum score | Mean | Maximum |
| --- | ---: | ---: | ---: |
| 1–100 | 21 | 37.60 | 64 |
| 101–200 | 49 | 72.14 | 93 |
| 201–300 | 53 | 73.72 | 101 |
| 301–400 | 88 | 114.73 | 137 |
| 401–500 | 94 | 116.89 | 150 |
| 501–600 | 91 | 117.61 | 141 |
| 601–700 | 101 | 119.31 | 140 |
| 701–800 | 100 | 120.05 | 141 |
| 801–900 | 98 | 123.37 | 140 |
| 901–1000 | 104 | 126.90 | 149 |

Checkpoint counts were 8 on 30 boards, 11 on 70, 14 on 302, 15 on 299, 16 on 200 and 17 on 99. The broad score bands have substantial overlap and a large step at level 301; these are explicit limitations to assess through playtesting.

This pre-release catalogue intentionally replaces earlier development puzzle layouts. It does not automatically erase wallets, entitlements or other data. Existing attempts are checked by the normal path validator and ignored if invalid, but older completion records do not establish equivalence with new boards. If a developer wants a fresh progression history, use Android Settings → Apps → Pathwise or Pathwise Debug → Storage → Clear storage on the intended development installation only; this also deletes that installation's local wallet and settings. Back up anything needed first.
