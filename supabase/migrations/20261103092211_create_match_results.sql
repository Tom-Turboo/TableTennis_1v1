/*
# Create match_results table for game stats (single-tenant, no auth)

1. New Tables
- `match_results`
  - `id` (uuid, primary key)
  - `player_name` (text, the display name entered by the player)
  - `winner` (smallint, 0 = left/blue, 1 = right/orange)
  - `left_score` (int, final score for the blue side)
  - `right_score` (int, final score for the orange side)
  - `longest_rally` (int, longest rally count reached during the match)
  - `created_at` (timestamp, when the match was recorded)

2. Security
- Enable RLS on `match_results`.
- Grant SELECT and INSERT to `anon` + `authenticated` so the no-auth
  frontend can read the leaderboard and submit finished match results.
  UPDATE and DELETE are intentionally NOT granted: once a result is
  recorded it cannot be changed or removed from the client, which
  protects the integrity of the leaderboard.
- Four public policies (select/insert only) using `USING (true)` /
  `WITH CHECK (true)` — the data is intentionally public and shared
  across all visitors (no accounts).
*/

CREATE TABLE IF NOT EXISTS match_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_name text NOT NULL,
  winner smallint NOT NULL,
  left_score int NOT NULL,
  right_score int NOT NULL,
  longest_rally int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE match_results ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON match_results TO anon, authenticated;

DROP POLICY IF EXISTS "public_select_matches" ON match_results;
CREATE POLICY "public_select_matches"
  ON match_results FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "public_insert_matches" ON match_results;
CREATE POLICY "public_insert_matches"
  ON match_results FOR INSERT
  TO anon, authenticated WITH CHECK (true);
