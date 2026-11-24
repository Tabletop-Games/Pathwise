# Internet requirement

Pathwise needs an internet connection to play. This applies to Levels, Daily Challenge, Time Attack, tutorials, the demo, rewards, purchases and the Fortune Wheel, for free and paid players alike.

## How connectivity is checked

`ConnectivityService` (`lib/logic/connectivity_service.dart`) is the only component that decides whether the player is online. Screens never probe the network themselves.

- **The probe** is an HTTPS request to `https://connectivitycheck.gstatic.com/generate_204`, with `https://www.google.com/generate_204` as a fallback. Both are Google-run endpoints that return HTTP 204 with no body. Android uses the same kind of endpoint to detect captive portals. Any other response, including a redirect or a sign-in page, counts as unreachable.
- **No developer server** is involved, and the request carries no identifiers.
- **Wi-Fi or mobile data alone is not enough.** The game is online only after a probe succeeds.
- **Brief drops are ignored.** The service reports offline only after two failed probes at least four seconds apart. A single dropped packet does not pause a puzzle.
- **Probing pauses in the background** and resumes on return. While offline, probes retry with backoff: 2, 4, 8 and 15 seconds at most.
- **Retry** runs an immediate probe.

The probe is not a security control. A determined user can bypass it, which is why the rewards and purchases also rely on Google Play and AdMob (see [cloud saves](cloud-saves.md#guarantees-and-their-limits)).

## What happens when the connection drops

- A **connection-lost overlay** covers the board. It is translucent, so the route stays visible, and it offers Retry.
- The **current stroke ends** at its last valid cell. The route, checkpoints, undo history and the hint state are kept in memory and in the device save.
- The **puzzle timer stops**. Time Attack's deadline keeps running on the device's elapsed-time clock, so going offline cannot extend a run. Clears made before the drop still count.
- **New puzzles, hints, purchases, rewards and the Wheel are refused** until the connection returns.
- **The unfinished route is saved** to the device, so it survives an app restart while offline.
- When the connection returns, the overlay disappears, play resumes from the same cell, and a pending cloud pass starts.

When the app starts without a connection, the same overlay appears as **No internet connection**, and nothing else is reachable until the probe succeeds.

## Why this design

- It satisfies the requirement without a backend.
- Google's own connectivity endpoints are reliable and widely used, and the app already depends on Google services.
- It is cheap: one 204 response every 20 seconds while in the foreground.
- Advertisements need a connection too, so an offline player cannot use the game to avoid ads. Advertisements can still fail to load while online, and gameplay never waits for one.
