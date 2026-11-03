# Project memory

## Product intent & audience

- Pong-like game (canvas-based, browser) with match results tracked as player stats.
- User wants stats to be "secure" — implying persistence and tamper resistance.
- Audience: players who care about leaderboards/progress integrity.
- Gameplay is being actively enriched with power-up mechanics.

## Brand personality & voice

- Helpful, consultative tone; presents tradeoffs clearly before implementing.
- Technical concepts explained in plain language.
- User writes casually; assistant matches with clear, friendly explanations.

## Visual design & UX direction

- HTML5 Canvas game; existing UI already reviewed by assistant.
- Gadgets drawn as distinct glowing shapes on canvas with unique colors:
  - Yellow lightning bolt, green star, pink spiral.
- Particle burst effect on gadget pickup.
- Gadgets blink when about to expire.
- Menu screen includes a gadget legend with styled legend elements.

## Decisions, constraints & rationale

- Current architecture: match results stored in `localStorage` — core security weakness.
- Sign-in approaches proposed (light vs full); user has not yet chosen; full sign-in recommended.
- No backend/auth/DB chosen yet.
- Gadgets feature implemented:
  - Spawn after every 3 paddle exchanges; random position; ~8s lifetime; max 2 at once.
  - **Speed Boost:** instantly speeds up ball on contact.
  - **Giant Paddle:** grows receiving-side paddle ~2x for ~5s.
  - **Curve Ball:** ball curves in S-pattern for ~4s.
- Build passes after gadget implementation.

## Open questions & assumptions

- Light vs full sign-in direction still undecided.
- Game engine/framework: appears to be vanilla JS + Canvas (not a named framework).
- Backend/database stack preference unknown.
- Cross-device stat syncing vs anti-cheat sole priority — unanswered.
- Leaderboards/multiplayer beyond single-player match results — unanswered.