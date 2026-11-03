# Project memory

## Product intent & audience

- Game application (genre/details not yet confirmed) where match results are tracked as player stats.
- User wants stats to be "secure" — implying persistence and tamper resistance.
- Audience likely includes players who care about leaderboards/progress integrity.

## Brand personality & voice

- Helpful, consultative tone; presents tradeoffs clearly rather than jumping to implementation.
- Technical concepts explained in plain language (e.g., localStorage weakness framed simply).

## Visual design & UX direction

- No design details inferred yet; game UI already exists (was reviewed by assistant).

## Decisions, constraints & rationale

- Current architecture: match results stored only in browser `localStorage` — identified as the core security weakness.
- Two approaches proposed; user has not yet chosen:
  - **Light (no sign-in):** server-side DB + leaderboard; still vulnerable to fake submissions.
  - **Full (with sign-in):** email/password accounts; server validates owner per result — recommended path for true security.
- Recommendation made: full version with sign-in.
- No backend, auth provider, or database chosen yet.

## Open questions & assumptions

- Which direction does the user want: light vs. full sign-in?
- What game engine/framework is being used? (assistant reviewed code but framework not recorded)
- What backend/database stack is available or preferred (e.g., Supabase, Firebase, custom API)?
- Is cross-device stat syncing required, or is anti-cheat the sole priority?
- Are there leaderboards or multiplayer components beyond single-player match results?