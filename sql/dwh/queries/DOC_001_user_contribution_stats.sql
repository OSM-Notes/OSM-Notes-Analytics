-- DOC-001: User Contribution Statistics
-- Shows how many users have made only one contribution and the distribution of users by contribution level
--
-- This query helps identify:
-- - Users with only one contribution (single-contribution users)
-- - Distribution of users by contribution level (1, 2-5, 6-10, 11-50, 51-100, 101-500, 501-1000, 1000+)
-- - Percentage of users in each category
-- - Total users for context
--
-- Created: 2025-01-27
-- Author: Andres Gomez (AngocA)

-- ============================================================================
-- Basic Query: Count users with only one contribution
-- ============================================================================
-- Source: original analytics backlog query
SELECT COUNT(*) AS users_with_single_contribution
FROM (
  SELECT f.action_dimension_id_user AS user_id
  FROM dwh.facts f
  GROUP BY f.action_dimension_id_user
  HAVING COUNT(*) = 1
) AS single_contributors;

-- ============================================================================
-- Enhanced Query: Distribution of users by contribution level
-- ============================================================================
-- Shows breakdown of users by number of contributions
WITH user_contributions AS (
  SELECT
    f.action_dimension_id_user AS user_id,
    COUNT(*) AS contribution_count
  FROM dwh.facts f
  GROUP BY f.action_dimension_id_user
),

contribution_buckets AS (
  SELECT
    CASE
      WHEN contribution_count = 1 THEN '1 contribution'
      WHEN contribution_count BETWEEN 2 AND 5 THEN '2-5 contributions'
      WHEN contribution_count BETWEEN 6 AND 10 THEN '6-10 contributions'
      WHEN contribution_count BETWEEN 11 AND 50 THEN '11-50 contributions'
      WHEN contribution_count BETWEEN 51 AND 100 THEN '51-100 contributions'
      WHEN contribution_count BETWEEN 101 AND 500 THEN '101-500 contributions'
      WHEN contribution_count BETWEEN 501 AND 1000 THEN '501-1000 contributions'
      ELSE '1000+ contributions'
    END AS contribution_level,
    contribution_count
  FROM user_contributions
),

level_stats AS (
  SELECT
    contribution_level,
    COUNT(*) AS user_count,
    SUM(contribution_count) AS total_contributions
  FROM contribution_buckets
  GROUP BY contribution_level
),

total_stats AS (
  SELECT
    COUNT(*) AS total_users,
    SUM(contribution_count) AS grand_total_contributions
  FROM user_contributions
)

SELECT
  ls.contribution_level,
  ls.user_count,
  ROUND(100.0 * ls.user_count / ts.total_users, 2) AS percentage_of_users,
  ls.total_contributions,
  ROUND(100.0 * ls.total_contributions / ts.grand_total_contributions, 2) AS percentage_of_contributions
FROM level_stats ls
CROSS JOIN total_stats ts
ORDER BY
  CASE ls.contribution_level
    WHEN '1 contribution' THEN 1
    WHEN '2-5 contributions' THEN 2
    WHEN '6-10 contributions' THEN 3
    WHEN '11-50 contributions' THEN 4
    WHEN '51-100 contributions' THEN 5
    WHEN '101-500 contributions' THEN 6
    WHEN '501-1000 contributions' THEN 7
    ELSE 8
  END;

-- ============================================================================
-- Summary Statistics
-- ============================================================================
-- Quick summary of user contribution patterns
WITH user_contributions AS (
  SELECT
    f.action_dimension_id_user AS user_id,
    COUNT(*) AS contribution_count
  FROM dwh.facts f
  GROUP BY f.action_dimension_id_user
)

SELECT
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE contribution_count = 1) AS users_with_single_contribution,
  ROUND(100.0 * COUNT(*) FILTER (WHERE contribution_count = 1) / COUNT(*), 2) AS percentage_single_contribution,
  COUNT(*) FILTER (WHERE contribution_count <= 5) AS users_with_5_or_less,
  ROUND(100.0 * COUNT(*) FILTER (WHERE contribution_count <= 5) / COUNT(*), 2) AS percentage_5_or_less,
  COUNT(*) FILTER (WHERE contribution_count <= 10) AS users_with_10_or_less,
  ROUND(100.0 * COUNT(*) FILTER (WHERE contribution_count <= 10) / COUNT(*), 2) AS percentage_10_or_less,
  SUM(contribution_count) AS total_contributions,
  ROUND(AVG(contribution_count), 2) AS avg_contributions_per_user,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY contribution_count) AS median_contributions,
  MIN(contribution_count) AS min_contributions,
  MAX(contribution_count) AS max_contributions
FROM user_contributions;

-- ============================================================================
-- View: User Contribution Distribution
-- ============================================================================
-- Creates a reusable view for easy access to contribution statistics
CREATE OR REPLACE VIEW dwh.v_user_contribution_distribution AS
WITH user_contributions AS (
  SELECT
    f.action_dimension_id_user AS user_id,
    COUNT(*) AS contribution_count
  FROM dwh.facts f
  GROUP BY f.action_dimension_id_user
),

contribution_buckets AS (
  SELECT
    CASE
      WHEN contribution_count = 1 THEN '1 contribution'
      WHEN contribution_count BETWEEN 2 AND 5 THEN '2-5 contributions'
      WHEN contribution_count BETWEEN 6 AND 10 THEN '6-10 contributions'
      WHEN contribution_count BETWEEN 11 AND 50 THEN '11-50 contributions'
      WHEN contribution_count BETWEEN 51 AND 100 THEN '51-100 contributions'
      WHEN contribution_count BETWEEN 101 AND 500 THEN '101-500 contributions'
      WHEN contribution_count BETWEEN 501 AND 1000 THEN '501-1000 contributions'
      ELSE '1000+ contributions'
    END AS contribution_level,
    contribution_count
  FROM user_contributions
),

level_stats AS (
  SELECT
    contribution_level,
    COUNT(*) AS user_count,
    SUM(contribution_count) AS total_contributions
  FROM contribution_buckets
  GROUP BY contribution_level
),

total_stats AS (
  SELECT
    COUNT(*) AS total_users,
    SUM(contribution_count) AS grand_total_contributions
  FROM user_contributions
)

SELECT
  ls.contribution_level,
  ls.user_count,
  ROUND(100.0 * ls.user_count / ts.total_users, 2) AS percentage_of_users,
  ls.total_contributions,
  ROUND(100.0 * ls.total_contributions / ts.grand_total_contributions, 2) AS percentage_of_contributions
FROM level_stats ls
CROSS JOIN total_stats ts
ORDER BY
  CASE ls.contribution_level
    WHEN '1 contribution' THEN 1
    WHEN '2-5 contributions' THEN 2
    WHEN '6-10 contributions' THEN 3
    WHEN '11-50 contributions' THEN 4
    WHEN '51-100 contributions' THEN 5
    WHEN '101-500 contributions' THEN 6
    WHEN '501-1000 contributions' THEN 7
    ELSE 8
  END;

-- ============================================================================
-- Function: Get User Contribution Summary
-- ============================================================================
-- Function to get summary statistics programmatically
CREATE OR REPLACE FUNCTION dwh.get_user_contribution_summary()
RETURNS TABLE (
  total_users BIGINT,
  users_with_single_contribution BIGINT,
  percentage_single_contribution NUMERIC,
  users_with_5_or_less BIGINT,
  percentage_5_or_less NUMERIC,
  users_with_10_or_less BIGINT,
  percentage_10_or_less NUMERIC,
  total_contributions BIGINT,
  avg_contributions_per_user NUMERIC,
  median_contributions NUMERIC,
  min_contributions BIGINT,
  max_contributions BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH user_contributions AS (
    SELECT
      f.action_dimension_id_user AS user_id,
      COUNT(1) AS contribution_count
    FROM dwh.facts f
    GROUP BY f.action_dimension_id_user
  )
  SELECT
    COUNT(*)::BIGINT AS total_users,
    COUNT(*) FILTER (WHERE contribution_count = 1)::BIGINT AS users_with_single_contribution,
    ROUND(100.0 * COUNT(*) FILTER (WHERE contribution_count = 1) / COUNT(*), 2) AS percentage_single_contribution,
    COUNT(*) FILTER (WHERE contribution_count <= 5)::BIGINT AS users_with_5_or_less,
    ROUND(100.0 * COUNT(*) FILTER (WHERE contribution_count <= 5) / COUNT(*), 2) AS percentage_5_or_less,
    COUNT(*) FILTER (WHERE contribution_count <= 10)::BIGINT AS users_with_10_or_less,
    ROUND(100.0 * COUNT(*) FILTER (WHERE contribution_count <= 10) / COUNT(*), 2) AS percentage_10_or_less,
    SUM(contribution_count)::BIGINT AS total_contributions,
    ROUND(AVG(contribution_count), 2) AS avg_contributions_per_user,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY contribution_count)::NUMERIC AS median_contributions,
    MIN(contribution_count)::BIGINT AS min_contributions,
    MAX(contribution_count)::BIGINT AS max_contributions
  FROM user_contributions;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Usage Examples
-- ============================================================================

-- Example 1: Get basic count of single-contribution users
-- SELECT COUNT(1) AS users_with_single_contribution
-- FROM (
--   SELECT f.action_dimension_id_user
--   FROM dwh.facts f
--   GROUP BY f.action_dimension_id_user
--   HAVING COUNT(1) = 1
-- ) AS t;

-- Example 2: Get distribution using the view
-- SELECT * FROM dwh.v_user_contribution_distribution;

-- Example 3: Get summary statistics using the function
-- SELECT * FROM dwh.get_user_contribution_summary();

-- Example 4: Get detailed breakdown
-- Run the "Enhanced Query: Distribution of users by contribution level" query above
