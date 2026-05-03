-- NULL-safe 24-feature vector for pgml.predict / predict_proba (order = train narrow views + ml_03).
-- Included from ml_01_setupPgML.sql and ml_03_predictWithPgML.sql (\ir from sql/dwh/ml/).

CREATE OR REPLACE FUNCTION dwh.note_ml_feature_vector(
  p_comment_length DOUBLE PRECISION,
  p_has_url_int DOUBLE PRECISION,
  p_has_mention_int DOUBLE PRECISION,
  p_hashtag_number DOUBLE PRECISION,
  p_total_comments_on_note DOUBLE PRECISION,
  p_hashtag_count DOUBLE PRECISION,
  p_has_fire_keyword DOUBLE PRECISION,
  p_has_air_keyword DOUBLE PRECISION,
  p_has_access_keyword DOUBLE PRECISION,
  p_has_campaign_keyword DOUBLE PRECISION,
  p_has_fix_keyword DOUBLE PRECISION,
  p_is_assisted_app DOUBLE PRECISION,
  p_is_mobile_app DOUBLE PRECISION,
  p_country_resolution_rate DOUBLE PRECISION,
  p_country_avg_resolution_days DOUBLE PRECISION,
  p_country_notes_health_score DOUBLE PRECISION,
  p_user_response_time DOUBLE PRECISION,
  p_user_total_notes DOUBLE PRECISION,
  p_user_experience_level DOUBLE PRECISION,
  p_user_contributor_type_id DOUBLE PRECISION,
  p_day_of_week DOUBLE PRECISION,
  p_hour_of_day DOUBLE PRECISION,
  p_month DOUBLE PRECISION,
  p_days_open DOUBLE PRECISION
) RETURNS DOUBLE PRECISION[]
LANGUAGE SQL
IMMUTABLE
PARALLEL UNSAFE
AS $fn$
SELECT ARRAY[
  COALESCE(p_comment_length, 0::DOUBLE PRECISION),
  COALESCE(p_has_url_int, 0::DOUBLE PRECISION),
  COALESCE(p_has_mention_int, 0::DOUBLE PRECISION),
  COALESCE(p_hashtag_number, 0::DOUBLE PRECISION),
  COALESCE(p_total_comments_on_note, 0::DOUBLE PRECISION),
  COALESCE(p_hashtag_count, 0::DOUBLE PRECISION),
  COALESCE(p_has_fire_keyword, 0::DOUBLE PRECISION),
  COALESCE(p_has_air_keyword, 0::DOUBLE PRECISION),
  COALESCE(p_has_access_keyword, 0::DOUBLE PRECISION),
  COALESCE(p_has_campaign_keyword, 0::DOUBLE PRECISION),
  COALESCE(p_has_fix_keyword, 0::DOUBLE PRECISION),
  COALESCE(p_is_assisted_app, 0::DOUBLE PRECISION),
  COALESCE(p_is_mobile_app, 0::DOUBLE PRECISION),
  COALESCE(p_country_resolution_rate, 0::DOUBLE PRECISION),
  COALESCE(p_country_avg_resolution_days, 0::DOUBLE PRECISION),
  COALESCE(p_country_notes_health_score, 0::DOUBLE PRECISION),
  COALESCE(p_user_response_time, 0::DOUBLE PRECISION),
  COALESCE(p_user_total_notes, 0::DOUBLE PRECISION),
  COALESCE(p_user_experience_level, 0::DOUBLE PRECISION),
  COALESCE(p_user_contributor_type_id, 0::DOUBLE PRECISION),
  COALESCE(p_day_of_week, 0::DOUBLE PRECISION),
  COALESCE(p_hour_of_day, 0::DOUBLE PRECISION),
  COALESCE(p_month, 0::DOUBLE PRECISION),
  COALESCE(p_days_open, 0::DOUBLE PRECISION)
]::DOUBLE PRECISION[];
$fn$;
