-- Create Badge System (DM-004)
-- Defines badges and creates procedure to assign them to users
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-27

-- Populate badges table: insert only badges that do not exist (safe for existing
-- installations where badges_per_users references badge_id; no DELETE to avoid FK violation).
INSERT INTO dwh.badges (badge_name, description)
SELECT v.badge_name, v.description
FROM (VALUES
  -- Milestone badges
  ('First Note'::VARCHAR(64), 'Opened your first note'::TEXT),
  ('First Close', 'Closed your first note'),
  ('First Comment', 'Made your first comment'),
  ('10 Notes Opened', 'Opened 10 notes'),
  ('50 Notes Opened', 'Opened 50 notes'),
  ('100 Notes Opened', 'Opened 100 notes'),
  ('500 Notes Opened', 'Opened 500 notes'),
  ('1000 Notes Opened', 'Opened 1,000 notes'),
  ('10 Notes Closed', 'Closed 10 notes'),
  ('50 Notes Closed', 'Closed 50 notes'),
  ('100 Notes Closed', 'Closed 100 notes'),
  ('500 Notes Closed', 'Closed 500 notes'),
  ('1000 Notes Closed', 'Closed 1,000 notes'),
  ('100 Comments', 'Made 100 comments'),
  ('500 Comments', 'Made 500 comments'),
  ('1000 Comments', 'Made 1,000 comments'),
  -- Activity badges
  ('Daily Contributor', 'Opened or closed notes on 7 consecutive days'),
  ('Weekly Contributor', 'Opened or closed notes for 4 consecutive weeks'),
  ('Monthly Contributor', 'Opened or closed notes for 3 consecutive months'),
  ('Consistent Helper', 'Closed notes for 30 consecutive days'),
  -- Achievement badges
  ('Speed Demon', 'Closed a note within 1 hour of opening'),
  ('Problem Solver', 'Closed 10 notes with explanatory comments'),
  ('Community Helper', 'Closed 50 notes with explanatory comments'),
  ('Resolution Master', 'Closed 100 notes with explanatory comments'),
  ('Hashtag Enthusiast', 'Used hashtags in 50+ notes'),
  ('Mobile User', 'Opened 100+ notes using mobile apps'),
  ('Desktop Power User', 'Opened 100+ notes using desktop apps'),
  -- Special badges
  ('Early Adopter', 'Opened notes in 2013 (first year of OSM Notes)'),
  ('Long Time Helper', 'Active for 5+ years'),
  ('Century Club', 'Opened 100+ notes in a single year'),
  ('Resolution Champion', 'Closed 100+ notes in a single year'),
  ('Comment King', 'Made 100+ comments in a single year'),
  ('Perfect Week', 'Opened or closed notes every day for a week'),
  ('Perfect Month', 'Opened or closed notes every day for a month'),
  -- Quality badges
  ('Quality Contributor', 'Average comment length > 50 characters'),
  ('Detail Oriented', 'Average comment length > 200 characters'),
  ('Collaborative', 'Used mentions in 20+ comments'),
  ('Resourceful', 'Included URLs in 20+ comments'),
  -- Extreme badges
  ('Note Master', 'Opened 5,000+ notes'),
  ('Resolution Legend', 'Closed 5,000+ notes'),
  ('Comment Legend', 'Made 5,000+ comments'),
  ('All Around Helper', 'Opened 1,000+, closed 1,000+, and commented 1,000+ times'),
  -- Motivation badges
  ('Global Resolver', 'Closed notes in 5+ countries'),
  ('First Responder', 'First to comment on 25+ notes'),
  ('Solid Closer', 'Closed 50+ notes that were never reopened'),
  ('Rising Resolver', 'Closed more notes this year than last year (min 10 this year)'),
  ('Local Hero', '80%+ of your closes in one country (min 50 closes)'),
  ('Closing Streak', 'Closed at least 1 note on 7 consecutive days')
) AS v(badge_name, description)
WHERE NOT EXISTS (SELECT 1 FROM dwh.badges b WHERE b.badge_name = v.badge_name);

-- Function to assign badges to a user based on their metrics
CREATE OR REPLACE FUNCTION dwh.assign_badges_to_user(p_dimension_user_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_badges_assigned INTEGER := 0;
  v_notes_opened INTEGER;
  v_notes_closed INTEGER;
  v_comments_count INTEGER;
  v_notes_closed_with_comment INTEGER;
  v_hashtags_used INTEGER;
  v_mobile_apps_count INTEGER;
  v_desktop_apps_count INTEGER;
  v_avg_comment_length DECIMAL;
  v_comments_with_url INTEGER;
  v_comments_with_mention INTEGER;
  v_first_note_year INTEGER;
  v_years_active INTEGER;
  v_notes_opened_this_year INTEGER;
  v_notes_closed_this_year INTEGER;
  v_comments_this_year INTEGER;
  v_consecutive_days INTEGER;
  v_badge_id INTEGER;
  -- New motivation badges
  v_countries_closed INTEGER := 0;
  v_first_responder_notes INTEGER := 0;
  v_solid_closes INTEGER := 0;
  v_notes_closed_last_year INTEGER := 0;
  v_max_closes_one_country INTEGER := 0;
  v_closing_streak_days INTEGER := 0;
BEGIN
  -- Get user metrics from datamart
  SELECT
    COALESCE(history_whole_open, 0),
    COALESCE(history_whole_closed, 0),
    COALESCE(history_whole_commented, 0),
    COALESCE(history_whole_closed_with_comment, 0),
    COALESCE(mobile_apps_count, 0),
    COALESCE(desktop_apps_count, 0),
    COALESCE(avg_comment_length, 0),
    COALESCE(comments_with_url_count, 0),
    COALESCE(comments_with_mention_count, 0),
    COALESCE(history_year_open, 0),
    COALESCE(history_year_closed, 0),
    COALESCE(history_year_commented, 0)
  INTO
    v_notes_opened,
    v_notes_closed,
    v_comments_count,
    v_notes_closed_with_comment,
    v_mobile_apps_count,
    v_desktop_apps_count,
    v_avg_comment_length,
    v_comments_with_url,
    v_comments_with_mention,
    v_notes_opened_this_year,
    v_notes_closed_this_year,
    v_comments_this_year
  FROM dwh.datamartusers
  WHERE dimension_user_id = p_dimension_user_id;

  -- Get first note year
  SELECT EXTRACT(YEAR FROM MIN(dd.date_id))
  INTO v_first_note_year
  FROM dwh.facts f
  JOIN dwh.dimension_days dd ON f.opened_dimension_id_date = dd.dimension_day_id
  WHERE f.opened_dimension_id_user = p_dimension_user_id
    AND f.action_comment = 'opened';

  -- Calculate years active
  IF v_first_note_year IS NOT NULL THEN
    v_years_active := EXTRACT(YEAR FROM CURRENT_DATE) - v_first_note_year;
  END IF;

  -- Get hashtag usage count
  SELECT COUNT(DISTINCT fh.fact_id)
  INTO v_hashtags_used
  FROM dwh.fact_hashtags fh
  JOIN dwh.facts f ON fh.fact_id = f.fact_id
  WHERE f.opened_dimension_id_user = p_dimension_user_id
    OR f.action_dimension_id_user = p_dimension_user_id;

  -- Global Resolver: distinct countries where user closed notes
  SELECT COUNT(DISTINCT f.dimension_id_country)
  INTO v_countries_closed
  FROM dwh.facts f
  WHERE f.closed_dimension_id_user = p_dimension_user_id
    AND f.action_comment = 'closed'
    AND f.dimension_id_country IS NOT NULL;

  -- First Responder: notes where this user was the first to comment
  SELECT COUNT(*)
  INTO v_first_responder_notes
  FROM (
    SELECT DISTINCT ON (f.id_note) f.id_note, f.action_dimension_id_user AS first_user
    FROM dwh.facts f
    WHERE f.action_comment = 'commented'
    ORDER BY f.id_note, f.action_at
  ) fc
  WHERE fc.first_user = p_dimension_user_id;

  -- Solid Closer: notes closed by user that were never reopened
  SELECT COUNT(*)
  INTO v_solid_closes
  FROM dwh.facts f
  WHERE f.closed_dimension_id_user = p_dimension_user_id
    AND f.action_comment = 'closed'
    AND NOT EXISTS (
      SELECT 1 FROM dwh.facts r
      WHERE r.id_note = f.id_note
        AND r.action_comment = 'reopened'
        AND r.action_at > f.action_at
    );

  -- Last year closes (for Rising Resolver)
  SELECT COUNT(*)
  INTO v_notes_closed_last_year
  FROM dwh.facts f
  WHERE f.closed_dimension_id_user = p_dimension_user_id
    AND f.action_comment = 'closed'
    AND f.action_at >= date_trunc('year', CURRENT_DATE - INTERVAL '1 year')
    AND f.action_at < date_trunc('year', CURRENT_DATE);

  -- Local Hero: max closes in a single country
  SELECT COALESCE(MAX(cnt), 0)
  INTO v_max_closes_one_country
  FROM (
    SELECT COUNT(*) AS cnt
    FROM dwh.facts f
    WHERE f.closed_dimension_id_user = p_dimension_user_id
      AND f.action_comment = 'closed'
      AND f.dimension_id_country IS NOT NULL
    GROUP BY f.dimension_id_country
  ) by_country;

  -- Closing Streak: max consecutive days with at least one close
  SELECT COALESCE(MAX(streak_len), 0)
  INTO v_closing_streak_days
  FROM (
    SELECT COUNT(*) AS streak_len
    FROM (
      SELECT (f.action_at::date) AS d,
             (f.action_at::date - row_number() OVER (ORDER BY (f.action_at::date))::integer) AS grp
      FROM dwh.facts f
      WHERE f.closed_dimension_id_user = p_dimension_user_id
        AND f.action_comment = 'closed'
      GROUP BY (f.action_at::date)
    ) with_grp
    GROUP BY grp
  ) streaks;

  -- Milestone badges - Notes Opened
  IF v_notes_opened >= 1 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'First Note';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_opened >= 10 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '10 Notes Opened';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_opened >= 50 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '50 Notes Opened';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_opened >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '100 Notes Opened';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_opened >= 500 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '500 Notes Opened';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_opened >= 1000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '1000 Notes Opened';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_opened >= 5000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Note Master';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Milestone badges - Notes Closed
  IF v_notes_closed >= 1 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'First Close';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed >= 10 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '10 Notes Closed';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed >= 50 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '50 Notes Closed';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '100 Notes Closed';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed >= 500 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '500 Notes Closed';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed >= 1000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '1000 Notes Closed';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed >= 5000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Resolution Legend';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Milestone badges - Comments
  IF v_comments_count >= 1 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'First Comment';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_count >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '100 Comments';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_count >= 500 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '500 Comments';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_count >= 1000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = '1000 Comments';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_count >= 5000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Comment Legend';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Quality badges
  IF v_notes_closed_with_comment >= 10 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Problem Solver';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed_with_comment >= 50 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Community Helper';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed_with_comment >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Resolution Master';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Special badges
  IF v_first_note_year = 2013 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Early Adopter';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_years_active >= 5 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Long Time Helper';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Year badges
  IF v_notes_opened_this_year >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Century Club';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_notes_closed_this_year >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Resolution Champion';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_this_year >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Comment King';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Quality badges
  IF v_avg_comment_length >= 50 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Quality Contributor';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_avg_comment_length >= 200 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Detail Oriented';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_with_mention >= 20 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Collaborative';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_comments_with_url >= 20 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Resourceful';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- App usage badges
  IF v_mobile_apps_count >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Mobile User';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  IF v_desktop_apps_count >= 100 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Desktop Power User';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Hashtag badge
  IF v_hashtags_used >= 50 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Hashtag Enthusiast';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- All around helper badge
  IF v_notes_opened >= 1000 AND v_notes_closed >= 1000 AND v_comments_count >= 1000 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'All Around Helper';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Global Resolver
  IF v_countries_closed >= 5 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Global Resolver';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- First Responder
  IF v_first_responder_notes >= 25 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'First Responder';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Solid Closer
  IF v_solid_closes >= 50 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Solid Closer';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Rising Resolver
  IF v_notes_closed_this_year >= 10 AND v_notes_closed_this_year > v_notes_closed_last_year THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Rising Resolver';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Local Hero
  IF v_notes_closed >= 50 AND v_max_closes_one_country >= (v_notes_closed * 0.8) THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Local Hero';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  -- Closing Streak
  IF v_closing_streak_days >= 7 THEN
    SELECT badge_id INTO v_badge_id FROM dwh.badges WHERE badge_name = 'Closing Streak';
    IF v_badge_id IS NOT NULL THEN
      INSERT INTO dwh.badges_per_users (id_user, id_badge, date_awarded)
      VALUES (p_dimension_user_id, v_badge_id, CURRENT_DATE)
      ON CONFLICT (id_user, id_badge) DO NOTHING;
      IF FOUND THEN v_badges_assigned := v_badges_assigned + 1; END IF;
    END IF;
  END IF;

  RETURN v_badges_assigned;
END;
$$;

COMMENT ON FUNCTION dwh.assign_badges_to_user IS
  'DM-004: Assigns badges to a user based on their metrics from datamartUsers. Returns number of new badges assigned.';

-- Procedure to assign badges to all users (can be called from datamartUsers.sh)
CREATE OR REPLACE PROCEDURE dwh.assign_badges_to_all_users()
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_record RECORD;
  v_total_assigned INTEGER := 0;
BEGIN
  RAISE NOTICE 'Starting badge assignment for all users...';

  FOR v_user_record IN
    SELECT dimension_user_id FROM dwh.datamartusers
  LOOP
    BEGIN
      v_total_assigned := v_total_assigned + dwh.assign_badges_to_user(v_user_record.dimension_user_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Error assigning badges to user %: %', v_user_record.dimension_user_id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE 'Badge assignment completed. Total badges assigned: %', v_total_assigned;
END;
$$;

COMMENT ON PROCEDURE dwh.assign_badges_to_all_users IS
  'DM-004: Assigns badges to all users in datamartUsers. Can be called after datamart update.';

