-- Backfill dwh.facts.comment_length (and has_url, has_mention) from public.note_comments_text
-- when the fact has NULL or zero comment_length (e.g. data loaded before column existed or via copy without body).
--
-- This allows history_whole_closed_with_comment and related metrics to be populated correctly.
--
-- Prerequisites:
--   - public.note_comments_text exists (local or FDW) with note_id, sequence_action, body
--
-- After running: refresh datamart users/countries so history_whole_closed_with_comment gets populated.
-- Usage: psql -d your_dwh -f sql/dwh/ETL_28_backfill_comment_length.sql

BEGIN;

WITH updated AS (
  UPDATE dwh.facts f
  SET
    comment_length = LENGTH(t.body),
    has_url       = (t.body ~ 'https?://'),
    has_mention   = (t.body ~ '@\w+')
  FROM public.note_comments_text t
  WHERE t.note_id = f.id_note
    AND t.sequence_action = f.sequence_action
    AND t.body IS NOT NULL
    AND (f.comment_length IS NULL OR f.comment_length = 0)
  RETURNING f.fact_id
)

SELECT COUNT(*) AS backfilled_count FROM updated;

COMMIT;
