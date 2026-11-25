# Design

The reverse journey puts new ground above the current position and old puzzles below. Chapter landscapes break up the route, with unopened and opened chest silhouettes showing the reward state. Home uses chapter progress and a fixed header. Research items use individual route, calendar, supply and timing marks. Boost coins sit inside a clock arc whose sweep represents relative duration. Larger tip portraits and smaller overhead silhouettes reuse their defining features and palette.

The journey derives an item offset from the level number. One fixed-extent cell per level and one per chest permit direct six-digit jumps. The save stores pending chest IDs and wallet claims. The multiplier and directional tip are confined to local widget state until the player selects a multiplier or commits a legal move. See the [economy and migration notes](../../../docs/quiet-journey.md).
