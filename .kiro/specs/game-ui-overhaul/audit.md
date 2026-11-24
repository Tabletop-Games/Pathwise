# Screen-by-screen audit

Status values: **Fixed** (changed and covered by tests/captures), **Kept** (reviewed, already acceptable), **Limit** (documented limitation). Findings were taken from the source at `09d1b7b`.

| # | Screen / state | Findings (before) | Resolution |
|---|---|---|---|
| 1 | Main menu | Tiny Store bag; redundant Themes tile; subtitle on every tile; flat text list | Full-width Store card after Time Attack; Themes tile and bag removed; compact Wheel card; Research/Boosts row; icon+counter header |
| 2 | Gameplay | Permanent instruction line; text progress row; plain buttons; custom tips unresponsive to drag; tip shrinks to a badge on checkpoints | Instruction removed (Help sheet + onboarding); pip progress; compact controls; continuous tip; checkpoint composition |
| 3 | Level select | Icon + number + word on every tile; "Current level" text button | Visual states only (check, play, lock), time on solved, current ring; icon button |
| 4 | Daily Challenge card | Date, subtitle, big button | Stage pips (3), time or Resume, single action |
| 5 | Time Attack setup | Three list tiles with prose | Three duration cards with best score, one Play action |
| 6 | Store shell | Material segmented control with outlines, horizontal scroll; default grey cards | Full-width themed selector; fixed header; flat cards |
| 7 | Themes catalogue | Mini board with fake header text; "N coins" text on every button | Board-only thumbnail; price pill; Apply; Equipped |
| 8 | Tips catalogue | Sideways polygons; same tonal button for everything | 20 upright illustrations; price pill / Apply / Equipped |
| 9 | Coins category | Prose list; milestone repeated three times; packs hidden when billing off | Reward card with pips; combined total; pack grid with unavailable state |
| 10 | Upgrades category | Three list tiles with sentences | Three illustrated cards, benefit chips, Play price, owned state; terms in an info sheet |
| 11 | Theme preview dialog | Fake Undo/Clear/Hint, "Close" | Board only, Apply/Buy action, close |
| 12 | Tip preview dialog | Four text buttons | Direction chips as arrows, board preview |
| 13 | Purchase dialogs | "Spend N coins to own..." | Item art, price pill, Unlock / Not now |
| 14 | Insufficient coins | Paragraph with balance maths | Item art, shortfall pill, Get coins |
| 15 | Contextual coin offer | Title and sentence | Coin art, +20, Watch / Not now |
| 16 | Hint shop | Two outlined buttons with prose | Two reward cards |
| 17 | Fortune Wheel | Chip; sentence title; text counters | Coin balance pill; reveal amount; compact buttons; cooldown pill |
| 18 | Research | Panel + paragraph; chips; cards with five text lines | Rank pips, `+4 → +6` comparison, price pill, prerequisite lock |
| 19 | Boosts | Panel + paragraph; cards with prose | Multiplier art, `2×` + duration, timer ring, inventory count |
| 20 | Supply crate | Prose dialog | Crate art, amount, Watch / Skip |
| 21 | Completion card | Check + title + subtitle + chip + coins + buttons | Emblem, reward amount, time, one primary action |
| 22 | Time Attack results | Seven list rows | Score hero, three stat tiles, actions |
| 23 | Streak | Large icon + text; icon-only week row; list tiles | Flame, week dots, milestone pips, freeze counter |
| 24 | Statistics | Nine rows in one card; separate cards per mode | Grouped stat tiles with icons |
| 25 | Achievements | ListTile with description + reward text | Emblem, progress state, reward pill |
| 26 | Settings | Long list; cloud section | Grouped sections, shared styling, same functions |
| 27 | Cloud save / conflict | Text-heavy | Kept structure and wording for destructive choices; shared card styling |
| 28 | Mechanic tutorial / demo | Multi-paragraph | Kept interactive board; shortened copy |
| 29 | Connection overlay | Already themed | Kept; shared button |
| 30 | Loading / error | Bare spinner / bare text | Themed spinner; message + retry |
| 31 | Developer dashboard | Debug only | Kept, debug-only |
