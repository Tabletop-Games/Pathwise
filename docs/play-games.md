# Play Games

The Android bridge uses Play Games Services v2. Configured players can sign in, open native achievement and leaderboard views, report unlocked local achievements and request a server authorization code. Offline play and local results do not depend on sign-in. The backend exchanges the authorization code and reads Google's authenticated player ID. The app's installation credential is then linked to that identity.

Console-generated IDs are supplied outside source control. [Publisher setup](../setup.md#5-before-enabling-play-games) lists the 15 local achievement keys and required OAuth configuration. Native leaderboard viewing is available; authoritative ranked submissions, score proofs, daily online rankings and Play Integrity are unfinished. The app offers no purchase-dependent ranked scoring.
