# Online-first architecture

Pathwise needs an authenticated session with a reachable backend for all normal play. That covers:

- Levels, Daily Challenge and Time Attack.
- Mechanic tutorials and the Level 1 demo.
- Every coin, hint, theme, research, boost and freeze purchase.
- Fortune Wheel, supply crates and rewarded videos.

Remove Ads and Premium remove automatic ads. They do not remove the connection requirement.

## Client

`lib/online/online_service.dart` is the only place that knows about connectivity, identity and sessions. Screens read its `phase`, and `ConnectionGate` (in `lib/views/connection_view.dart`) covers the whole app whenever the phase is not `online`. No individual screen checks the network.

| Phase | Shown as |
| --- | --- |
| `starting` | Connecting, with a progress indicator |
| `noInternet` | No internet connection, or "Connection lost" during play |
| `backendUnavailable` | Pathwise is unavailable, or "Reconnecting" during play |
| `authFailed` | Couldn't verify this device |
| `sessionExpired` | Session expired, with Restore with Google Play Games and Start a new profile |
| `updateRequired` | Update required |
| `notConfigured` | Not connected to a game server (a build without `PATHWISE_API_BASE`) |

Reachability means the backend answered. Wi-Fi or mobile data alone does not count. A request to `gstatic.com/generate_204` is used only to tell "no internet" from "our server is down". The heartbeat pings `/v1/ping` every 15 seconds while the app is in the foreground. One failed ping triggers a second check after 4 seconds, and play pauses only when both fail. Recovery retries with backoff of 2, 4, 8, 16 and then 30 seconds, plus random jitter.

### Startup

1. The Android native launch screen stays up while the save cache loads.
2. The app then waits up to 3 seconds for the service to fetch `/v1/config`, restore or create the identity, refresh the session, deliver queued commands and load `/v1/state`.
3. If startup isn't finished, the themed connection screen takes over and startup continues. The splash is never held indefinitely.

### Gameplay

The puzzle engine stays on the device. Dragging, rejection animations, haptics, undo, clear, ice, portals and gates run locally. The client contacts the server only at meaningful points:

| Moment | Request |
| --- | --- |
| Opening a puzzle | `play.start` |
| Revealing a hint | `hint.use` |
| Between strokes, debounced to 5 seconds, and on leaving or backgrounding | `attempt.save` |
| A finished route | `play.complete`, or `attack.clear` in Time Attack |

While disconnected:

- The active stroke ends, input and the play clock stop, and the route and checkpoints stay in memory and in the local cache.
- New puzzles and purchases are refused.
- Commands that must not be lost, such as a hint already shown, go to a persisted outbox. Each keeps its operation ID and is delivered in order after reconnecting, so it is never charged twice.
- Time Attack deadlines run on the server clock. Disconnecting does not stop the clock, and a board submitted after the deadline does not count.

### Authority

`AppModel` keeps the existing local rules for instant feedback, but the server's answer is authoritative:

- Spends are predicted locally, then confirmed. Every response's wallet replaces the cached balance, inventory, entitlements and limits.
- Rewards are never predicted. A rewarded video pays only after the server confirms Google's signed callback.
- A rejected command triggers a full state refresh.
- Fortune Wheel prizes are chosen by the server and credited when the client reports that the spin animation settled. An interrupted spin is restored from the server's pending prize.
- Supply crate offers and prizes are chosen by the server on its own schedule.

The local save (`pathwise.save.v1`) is now only a cache. Editing it changes nothing the server trusts.

## Server

See [backend](backend.md) for modules, the API and its guarantees, and [deployment](deployment.md) for setup.

Completion validation regenerates the board from its ID with the same generator and movement rules as the app. It accepts a route only if:

- The route covers every cell legally and ends on the finish.
- The puzzle was started and is unlocked.
- The claimed time is at least 30 ms per cell and no longer than the time the server observed.

This proves a legal solution and bounds the timing. It cannot prove a human solved the puzzle, because the solver ships in the client.

## Conflicts and cross-device play

- Saved attempts carry a revision. A save based on an older revision is rejected with the current attempt, so stale devices cannot overwrite newer routes.
- Results only improve, and first-clear rewards are paid once per puzzle.
- The device that is actively playing keeps its local route until it saves.
- Linking Play Games makes the profile recoverable on any device. Purchases and entitlements are stored server-side and restore with the profile.
