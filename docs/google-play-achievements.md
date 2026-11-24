# Google Play Games achievements

## Baseline audit

Build 7 used the Android Play Games Services v2 SDK, optional sign-in, native achievement and leaderboard intents, and optional server account linking. It mapped 16 local coin achievements to standard unlock calls on explicit request. Build 7 had no native incremental progress, hidden catalog, persisted offline synchronization, account-specific confirmation, or readback of Google's achievement state. Native leaderboards were available for viewing when configured. There was no verified score submission or ranking.

## Publisher configuration

1. In Play Console open **Grow users → Play Games Services → Setup and management → Configuration**. Create or select the Play Games Services project for Pathwise. Associate `games.tabletop.pathwise` with an Android OAuth credential. Enter the SHA-1 for the app signing certificate in **Test and release → Setup → App integrity**. Register a second Android credential with the SHA-1 of the relevant debug or sideload signing certificate for those builds. Link the same OAuth project. Use the numeric Play Games project ID as the `PATHWISE_GAMES_PROJECT_ID` build environment variable. [Official Play Games Services v2 setup](https://developer.android.com/games/pgs/console/setup)
2. Make the achievement definitions in **Play Games Services → Setup and management → Achievements**. For a new project, use **Import → Bulk import** with the ZIP below. Google creates the resource IDs. The catalog assigns 20 points per definition. Standard entries have no step count. In a project with development achievements, reuse IDs only where the name, type, initial state, step total, and unlock criterion all match. [Official achievement setup and import](https://developer.android.com/games/pgs/integrate-achievements)
3. Copy [the ID template](../config/play-games-achievements.example.json) outside the repository. Replace each placeholder with the generated resource ID from the achievement's details. Use one distinct ID per key. Place the compact JSON map as a **string** in the external Dart configuration field `PATHWISE_GAMES_ACHIEVEMENTS`. Set `PATHWISE_GAMES_ENABLED` to true in that config. The commands below assume `jq` and the paths from [setup.md](../setup.md).

```sh
jq -e '[.[] | startswith("REPLACE_")] | any | not' /secure/pathwise-achievement-ids.json
jq --arg ids "$(jq -c . /secure/pathwise-achievement-ids.json)" \
  '.PATHWISE_GAMES_ENABLED = "true" | .PATHWISE_GAMES_ACHIEVEMENTS = $ids' \
  /secure/pathwise-production.json > /secure/pathwise-production.next.json &&
  mv /secure/pathwise-production.next.json /secure/pathwise-production.json
```

4. In **Play Games Services → Setup and management → Testers**, add the Google accounts or enable the app's internal test track. Use the corresponding tester account in Play Games on a Play-certified phone. Install the matching signed build. The Android credential suffices for basic achievements. Online account linking uses the separate server OAuth configuration described in [setup.md](../setup.md).
5. Open **Settings → Google Play Achievements → Open Google Play Achievements**. Complete sign-in if prompted. With a fresh save and test account, solve Level 1 and confirm First Steps in Google's native activity. Complete more fresh boards and confirm Getting Started tracks their number. Complete an unplayed board offline, restart offline, verify the local or pending status, reconnect, and verify the remote step count increases exactly once. Verify an unfinished Hidden achievement does not expose its description. Switch the game's account in Play Games settings, return to Pathwise, and verify status for the previous account disappears. On a second device using the same test account, confirm the unlock appears without adding coins. The catalog lists the eligibility to exercise each definition.
6. Publish the Play Games Services configuration after internal testing. Publishing this configuration and rolling out the Android listing are separate Play Console actions.

### Import archive and icons

```sh
dart run tool/export_play_games_achievements.dart /secure/pathwise-pgs-import
(cd /secure/pathwise-pgs-import && zip /secure/pathwise-pgs-achievements.zip *.csv *.png)
```

The archive has the two headerless Console CSV files and seven original 512×512 PNG category icons. Google derives the grayscale/revealed treatment from the unlocked image and masks its outer corners in native toasts. For manual entry, choose the matching icon from [the PNG directory](media/play-games). These publisher assets are outside the Android bundle. [Google icon specifications](https://developer.android.com/games/pgs/integrate-achievements#icon-guidelines)

## Eligibility and synchronization

Progression puzzle counters use unique Levels and Daily results, historical Endless results if present, and lifetime clears migrated from retired modes. Time Attack achievements use archived timed runs at 100 points per solve. The thresholds are three, six and ten solves within 10 minutes. Automated tests exercise the scoring and expiration with ten 55-second fixture clears. Human performance on generated boards has not been measured.

Precision requires a first clear without Clear or hints. Research counts recorded rank purchases, and the theme metric counts individual theme ownership. The starter palettes, All Themes Forever, and Premium add no steps directly. A Legendary achievement requires collecting the crate. Achievements grant no hints. Sharing and Play Games synchronization trigger no coin payout. Internal coin achievements use their independent wallet transaction IDs.

Native Daily milestones start recording with build 8. Dates must advance and at least 20 hours of monotonic Android time must separate qualifying records. Across a reboot, current uptime must itself prove that interval. A backward clock or rapid future-date changes cannot manufacture a series of eligible solves. This conservative rule can skip valid Daily solves less than 20 hours apart or soon after a reboot. Existing local Daily results and streaks are available as before. The native catalog uses cumulative Daily counts, with no clock-only streak achievement. Build 7 saves retain their general progression and game records. Historical Clear use and eligibility timing cannot be reconstructed reliably.

The local versioned snapshot records progress and recent account-specific confirmations. The SDK checks the active player before and after reads and before updates. The view labels confirmation after a fresh, non-stale Google response. Standard achievements use `unlockImmediate`. Incremental achievements use absolute `setStepsImmediate`, capped at the Console step count. Higher remote progress wins. Hidden incremental entries send the full step target at eligibility to keep them secret until earned. The app skips missing, duplicate or incompatible IDs. Pending progress is retried on resume, when qualifying counters change, and periodically in the foreground. Drawing a route can defer synchronization.

The local save is installation-wide. The first Play Games account to reconcile eligible records claims this save's achievement progress. Switching to another account still opens its native achievements. Return to the linked account to send this save's pending progress. The app refreshes account state before labeling an achievement confirmed. Google account achievements can appear on another device. Puzzle progress, coins and other save data require separate synchronization. This integration provides neither server proof for offline achievements nor ranked leaderboard submission. Time Attack result sharing omits rankings. Runtime tests on signed, publisher-configured Android builds remain required.

## Achievement inventory

Each row supplies the Console display name, description, type, initial state, steps for incremental entries, and icon. Use the configuration key to enter the resource ID assigned by Google.
| Configuration key | Achievement | Description and unlock condition | Type | Initial state | Console steps | Icon | Google ID |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `firstSteps` | First Steps | Solve your first progression puzzle. | Standard | Revealed | — | progression.png | Publisher ID pending |
| `gettingStarted` | Getting Started | Solve 10 progression puzzles. | Incremental | Revealed | 10 | progression.png | Publisher ID pending |
| `apprentice` | Puzzle Apprentice | Solve 50 progression puzzles. | Incremental | Revealed | 50 | progression.png | Publisher ID pending |
| `enthusiast` | Puzzle Enthusiast | Solve 100 progression puzzles. | Incremental | Revealed | 100 | progression.png | Publisher ID pending |
| `expert` | Puzzle Expert | Solve 500 progression puzzles. | Incremental | Revealed | 500 | progression.png | Publisher ID pending |
| `master` | Puzzle Master | Solve 1,000 progression puzzles. | Incremental | Revealed | 1000 | progression.png | Publisher ID pending |
| `legend` | Puzzle Legend | Solve 5,000 progression puzzles. | Incremental | Revealed | 5000 | progression.png | Publisher ID pending |
| `immortal` | Puzzle Immortal | Solve 10,000 progression puzzles. | Incremental | Hidden | 10000 | progression.png | Publisher ID pending |
| `independent` | Independent Thinker | Solve a progression puzzle without hints. | Standard | Revealed | — | skill.png | Publisher ID pending |
| `cleanSweep` | Clean Sweep | Solve 25 progression puzzles without hints. | Incremental | Revealed | 25 | skill.png | Publisher ID pending |
| `untouchable` | Untouchable | Solve 100 progression puzzles without hints. | Incremental | Revealed | 100 | skill.png | Publisher ID pending |
| `pureLogic` | Pure Logic | Solve 500 progression puzzles without hints. | Incremental | Revealed | 500 | skill.png | Publisher ID pending |
| `firstTry` | First-Try Genius | Solve a fresh progression puzzle without using Clear or hints. | Standard | Revealed | — | skill.png | Publisher ID pending |
| `precision` | Perfect Precision | Solve 100 fresh progression puzzles without using Clear or hints. | Incremental | Revealed | 100 | skill.png | Publisher ID pending |
| `dailyDiscovery` | Daily Discovery | Solve your first eligible Daily Challenge. | Standard | Revealed | — | daily.png | Publisher ID pending |
| `dailyRoutine` | Daily Routine | Solve 7 eligible Daily Challenges. | Incremental | Revealed | 7 | daily.png | Publisher ID pending |
| `dailyDevotion` | Daily Devotion | Solve 30 eligible Daily Challenges. | Incremental | Revealed | 30 | daily.png | Publisher ID pending |
| `dailyVeteran` | Daily Veteran | Solve 100 eligible Daily Challenges. | Incremental | Revealed | 100 | daily.png | Publisher ID pending |
| `dailyLegend` | Daily Legend | Solve 365 eligible Daily Challenges. | Incremental | Hidden | 365 | daily.png | Publisher ID pending |
| `againstTheClock` | Against the Clock | Finish a Time Attack session with at least one solve. | Standard | Revealed | — | attack.png | Publisher ID pending |
| `quickDraw` | Quick Draw | Score 300 points in a single Time Attack session. | Standard | Revealed | — | attack.png | Publisher ID pending |
| `speedSolver` | Speed Solver | Score 600 points in a single Time Attack session. | Standard | Revealed | — | attack.png | Publisher ID pending |
| `timeLord` | Time Lord | Score 1,000 points in a single Time Attack session. | Standard | Hidden | — | attack.png | Publisher ID pending |
| `firstInvestment` | First Investment | Purchase your first Research rank. | Standard | Revealed | — | research.png | Publisher ID pending |
| `researcher` | Researcher | Purchase 25 Research ranks. | Incremental | Revealed | 25 | research.png | Publisher ID pending |
| `masterResearcher` | Master Researcher | Purchase 100 Research ranks. | Incremental | Revealed | 100 | research.png | Publisher ID pending |
| `themeCollector` | Theme Collector | Individually unlock 5 themes through Themes. | Incremental | Revealed | 5 | themes.png | Publisher ID pending |
| `styleMaster` | Style Master | Individually unlock 15 themes through Themes. | Incremental | Revealed | 15 | themes.png | Publisher ID pending |
| `luckyFind` | Lucky Find | Collect a Legendary supply crate. | Standard | Hidden | — | crates.png | Publisher ID pending |
