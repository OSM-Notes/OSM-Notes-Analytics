---
title: "Metric Definitions - Complete Reference"
description:
  "This document provides comprehensive business definitions for all metrics available in the"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Metric Definitions - Complete Reference

This document provides comprehensive business definitions for all metrics available in the
OSM-Notes-Analytics datamarts (77+ metrics for countries, 78+ metrics for users). Each metric
includes business name, definition, calculation formula, unit, interpretation, and use cases.

## Table of Contents

- [Overview](#overview)
- [Metric Categories](#metric-categories)
  - [1. Historical Count Metrics](#1-historical-count-metrics)
    - [1.1 Whole History Metrics](#11-whole-history-metrics)
    - [1.2 Time Period Metrics](#12-time-period-metrics)
  - [2. Resolution Metrics](#2-resolution-metrics)
  - [3. Application Statistics](#3-application-statistics)
  - [4. Content Quality Metrics](#4-content-quality-metrics)
  - [5. Temporal Pattern Metrics](#5-temporal-pattern-metrics)
  - [6. Geographic Pattern Metrics](#6-geographic-pattern-metrics)
  - [7. Community Health Metrics](#7-community-health-metrics)
  - [8. User Behavior Metrics](#8-user-behavior-metrics)
  - [9. Hashtag Metrics](#9-hashtag-metrics)
  - [10. First/Last Action Metrics](#10-firstlast-action-metrics)
  - [11. Current Period Metrics](#11-current-period-metrics)
  - [12. User Classification Metrics](#12-user-classification-metrics)
- [Metric Summary Table](#metric-summary-table)
  - [User Datamart Metrics (78+ metrics)](#user-datamart-metrics-78-metrics)
  - [Country Datamart Metrics (77+ metrics)](#country-datamart-metrics-77-metrics)
- [Metric Calculation Details](#metric-calculation-details)
- [Metric Interpretation Guide](#metric-interpretation-guide)
  - [Understanding Metric Values](#understanding-metric-values)
  - [Comparing Metrics](#comparing-metrics)
- [Related Documentation](#related-documentation)
- [References](#references)

---

## Overview

The datamarts contain pre-computed metrics organized into categories:

- **Historical Counts**: Activity counts by time period
- **Resolution Metrics**: Time to resolution and resolution rates
- **Application Statistics**: Tool usage patterns and trends
- **Content Quality Metrics**: Comment analysis
- **Temporal Patterns**: Time-based activity patterns
- **Geographic Patterns**: Location-based metrics
- **Community Health**: Backlog and activity indicators
- **User Behavior**: User responsiveness and collaboration patterns
- **Hashtag Metrics**: Campaign and organization tracking

**Total Metrics**:

- **77+ metrics** per country
- **78+ metrics** per user (includes `notes_opened_but_not_closed_by_user` added December 2025)

---

## Metric Categories

### 1. Historical Count Metrics

These metrics count note actions (opened, commented, closed, reopened) across different time
periods.

#### 1.1 Whole History Metrics

##### `history_whole_open`

**Business Name**: Total Notes Created (All Time)  
**Definition**: Total number of notes this user (or country) opened/created since 2013.  
**Formula**: `COUNT(*) WHERE action_dimension_id_user = user AND action_comment = 'opened'`  
**Unit**: Count (integer)  
**Interpretation**:

- **High values** (>1000): Very active contributor/community
- **Medium values** (100-1000): Active contributor/community
- **Low values** (<100): Occasional contributor/community

**Use Cases**:

- User profile: "This user has created 1,234 notes"
- Country comparison: "Colombia has 50,000 notes created"
- Leaderboards: "Top 10 users by notes created"

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_whole_commented`

**Business Name**: Total Comments Added (All Time)  
**Definition**: Total number of comments added to notes (excluding opening/closing comments).  
**Formula**: `COUNT(*) WHERE action_comment = 'commented'`  
**Unit**: Count (integer)  
**Interpretation**:

- **High values**: Active discussion participant
- **Low values**: Creates notes but doesn't engage in discussion

**Use Cases**:

- Engagement measurement: "This user actively participates in discussions"
- Community collaboration: "High comment counts show active community"

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_whole_closed`

**Business Name**: Total Notes Resolved (All Time)  
**Definition**: Number of close events (actions) by this user—one per close action. Same note closed twice = 2. For distinct notes, use notes_resolved_count.  
**Formula**: `COUNT(*) FROM facts WHERE action_dimension_id_user = user AND action_comment = 'closed'` (count of **events**, not distinct notes).  
**See also**: `notes_resolved_count` = `COUNT(DISTINCT id_note)` for closes by this user (same note closed twice = 1). So `history_whole_closed` ≥ `notes_resolved_count`.  
**Unit**: Count (integer)  
**Interpretation**:

- **High values**: Very active resolver
- **Key indicator**: Shows contribution to note resolution

**Use Cases**:

- User profile: "This user has resolved 567 notes"
- Country comparison: "Germany has resolved 80% of its notes"
- Impact measurement: "This user's resolution activity helps the community"

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_whole_closed_with_comment`

**Business Name**: Resolved Notes with Explanations (All Time)  
**Definition**: Number of notes closed that include an explanatory comment.  
**Formula**: `COUNT(*) WHERE action_comment = 'closed' AND comment_text IS NOT NULL`  
**Unit**: Count (integer)  
**Interpretation**:

- **High percentage** (>80%): Good communication practices
- **Low percentage** (<50%): May indicate rushed closures

**Use Cases**:

- Quality measurement: "80% of resolutions include explanations"
- User behavior: "This user always explains their resolutions"
- Community standards: "Our community values explanatory closures"

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_whole_reopened`

**Business Name**: Total Notes Reopened (All Time)  
**Definition**: Number of times notes were reopened after being closed.  
**Formula**: `COUNT(*) WHERE action_comment = 'reopened'`  
**Unit**: Count (integer)  
**Interpretation**:

- **High values**: May indicate complex issues or quality problems
- **Low values**: Good resolution quality

**Use Cases**:

- Problem identification: "This note was reopened 3 times (complex issue)"
- Quality measurement: "Low reopen rate indicates good resolution quality"
- User behavior: "This user reopens notes that weren't properly fixed"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 1.2 Time Period Metrics

These metrics follow the same pattern as whole history but for specific time periods:

##### `history_year_open`, `history_year_commented`, `history_year_closed`, etc.

**Business Name**: Notes Created This Year  
**Definition**: Count of notes opened in the current year.  
**Formula**: `COUNT(*) WHERE action_comment = 'opened' AND action_dimension_id_date IN (SELECT dimension_day_id FROM dimension_days WHERE year = CURRENT_YEAR)`  
**Unit**:
Count (integer)  
**Interpretation**: Shows current year activity level

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_month_open`, `history_month_commented`, `history_month_closed`, etc.

**Business Name**: Notes Created This Month  
**Definition**: Count of notes opened in the current month.  
**Formula**: Similar to year but filtered by current month  
**Unit**: Count (integer)  
**Interpretation**: Shows recent activity (last 30 days)

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_day_open`, `history_day_commented`, `history_day_closed`, etc.

**Business Name**: Notes Created Today  
**Definition**: Count of notes opened today.  
**Formula**: Similar to month but filtered by current day  
**Unit**: Count (integer)  
**Interpretation**: Shows today's activity

**Available In**: `datamartusers`, `datamartcountries`

---

##### `history_YYYY_open`, `history_YYYY_commented`, `history_YYYY_closed`, etc.

**Business Name**: Notes Created in Year YYYY  
**Definition**: Count of notes opened in a specific year (2013-2024+).  
**Formula**: `COUNT(*) WHERE action_comment = 'opened' AND action_dimension_id_date IN (SELECT dimension_day_id FROM dimension_days WHERE year = YYYY)`  
**Unit**:
Count (integer)  
**Interpretation**: Shows activity for that specific year

**Available In**: `datamartusers`, `datamartcountries`  
**Note**: One column per year (2013, 2014, 2015, ..., 2024, 2025, etc.)

---

### 2. Resolution Metrics

Metrics related to note resolution time and rates.

#### 2.1 `avg_days_to_resolution`

**Business Name**: Average Resolution Time  
**Definition**: Average number of days from when a note is opened until it is closed.  
**Formula**: `AVG(days_to_resolution) WHERE days_to_resolution IS NOT NULL`  
**Unit**: Days (decimal, e.g., 15.5)  
**Interpretation**:

- **Excellent**: < 7 days
- **Good**: 7-30 days
- **Acceptable**: 30-90 days
- **Needs Improvement**: > 90 days

**Use Cases**:

- Performance measurement: "Average resolution time is 15 days"
- Community comparison: "Country A resolves notes 2x faster than Country B"
- Trend analysis: "Resolution time improved from 45 to 20 days this year"

**Available In**: `datamartusers`, `datamartcountries`  
**Note**: Only includes notes that have been closed. Open notes are excluded.

---

#### 2.2 `median_days_to_resolution`

**Business Name**: Median Resolution Time  
**Definition**: The middle value when all resolution times are sorted (50th percentile).  
**Formula**: `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution)`  
**Unit**: Days (decimal)  
**Interpretation**: Less affected by outliers than average. If median is much lower than average,
there are some very long-resolution notes skewing the average.

**Use Cases**:

- Robust performance measurement: "Median resolution time is 8 days (vs 15 day average)"
- Outlier identification: "Average is high due to a few very old notes"
- Community health: "50% of notes resolve within 8 days"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 2.3 `resolution_rate`

**Business Name**: Note Resolution Rate  
**Definition**: Percentage of opened notes that have been closed (resolved).  
**Formula**: `(COUNT(*) WHERE action_comment = 'closed') / (COUNT(*) WHERE action_comment = 'opened') * 100`  
**Unit**:
Percentage (0-100, decimal)  
**Interpretation**:

- **Excellent**: > 80%
- **Good**: 60-80%
- **Acceptable**: 40-60%
- **Needs Improvement**: < 40%

**Use Cases**:

- Community health: "Colombia has an 85% resolution rate"
- Trend analysis: "Resolution rate improved from 60% to 75% this year"
- Comparison: "Country A resolves 90% of notes, Country B resolves 50%"

**Available In**: `datamartusers`, `datamartcountries`  
**Note**: This is a ratio, not a count. A rate of 75% means 3 out of 4 notes are resolved.

---

#### 2.4 `notes_resolved_count`

**Business Name**: Number of Notes Resolved  
**Definition**: Count of **distinct notes** that this user has closed (resolved). Each note is counted at most once, even if the user closed it, it was reopened, and they closed it again.  
**Formula**: `COUNT(DISTINCT id_note) FROM facts WHERE closed_dimension_id_user = user AND action_comment = 'closed'`  
**Unit**: Count (integer)  
**See also**: `history_whole_closed` = number of close **events** (actions); same note closed twice by the user counts as 2 there, 1 here.  
**Interpretation**: Absolute number of distinct notes resolved by this user

**Use Cases**:

- Absolute measurement: "This user has resolved 500 notes"
- Comparison: "Country A has resolved 10,000 notes vs Country B's 5,000"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 2.5 `notes_still_open_count`

**Business Name**: Unresolved Notes Count  
**Definition**: Number of notes opened but never closed.  
**Formula**: `COUNT(DISTINCT id_note) WHERE action_comment = 'opened' AND id_note NOT IN (SELECT DISTINCT id_note WHERE action_comment = 'closed')`  
**Unit**:
Count (integer)  
**Interpretation**:

- **High values**: Large backlog
- **Low values**: Good resolution coverage

**Use Cases**:

- Backlog measurement: "This user has 50 unresolved notes"
- Community health: "Country has 1,000 unresolved notes (backlog)"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 2.6 `resolution_by_year`

**Business Name**: Resolution Metrics by Year  
**Definition**: JSON array containing resolution metrics (average days, median days, resolution
rate) for each year.  
**Formula**: `json_agg(json_build_object('year', year, 'avg_days', avg_days, 'median_days', median_days, 'resolution_rate', resolution_rate)) GROUP BY year`  
**Unit**:
JSON array  
**Format**: `[{"year": 2023, "avg_days": 15.5, "median_days": 8.0, "resolution_rate": 75.0}, ...]`  
**Interpretation**: Shows resolution trends over time

**Use Cases**:

- Trend analysis: "Resolution time improved from 30 days (2020) to 15 days (2024)"
- Year-over-year comparison: "2024 resolution rate is 10% higher than 2023"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 2.7 `resolution_by_month`

**Business Name**: Resolution Metrics by Month  
**Definition**: JSON array containing resolution metrics for each month.  
**Formula**: Similar to `resolution_by_year` but grouped by year and month  
**Unit**: JSON array  
**Format**: `[{"year": 2024, "month": 1, "avg_days": 14.2, "median_days": 7.5, "resolution_rate": 78.0}, ...]`  
**Interpretation**:
Shows monthly resolution trends

**Use Cases**:

- Monthly trends: "Resolution time varies by month (seasonal patterns)"
- Short-term analysis: "Last 3 months show improving resolution rates"

**Available In**: `datamartusers`, `datamartcountries`

---

### 3. Application Statistics

Metrics related to applications and tools used to create notes.

#### 3.1 `applications_used`

**Business Name**: Applications Used  
**Definition**: JSON array of distinct applications used to create notes.  
**Formula**: `json_agg(DISTINCT dimension_application_creation) WHERE dimension_application_creation IS NOT NULL`  
**Unit**:
JSON array of application IDs  
**Format**: `[1, 5, 12, 23]` (application dimension IDs)  
**Interpretation**: Shows tool diversity

**Use Cases**:

- Tool diversity: "This user uses 5 different applications"
- Technology adoption: "Country uses diverse mapping tools"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 3.2 `most_used_application_id`

**Business Name**: Primary Application  
**Definition**: The application most frequently used to create notes.  
**Formula**: `MODE() WITHIN GROUP (ORDER BY dimension_application_creation)`  
**Unit**: Application ID (integer, FK to dimension_applications)  
**Interpretation**: Shows the preferred tool for note creation

**Use Cases**:

- Tool popularity: "iD is the most used application in this country"
- User preference: "This user primarily uses JOSM"
- Platform trends: "Mobile apps are becoming the primary tool"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 3.3 `mobile_apps_count`

**Business Name**: Number of Mobile Apps Used  
**Definition**: Count of distinct mobile applications used to create notes.  
**Formula**: `COUNT(DISTINCT dimension_application_creation) WHERE platform = 'mobile'`  
**Unit**: Count (integer)  
**Interpretation**:

- **High values**: Diverse mobile app usage
- **Zero**: No mobile app usage

**Use Cases**:

- Platform adoption: "Users in this country use 5 different mobile apps"
- Technology trends: "Mobile app usage increased 30% this year"
- User behavior: "This user creates notes from 3 different mobile apps"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 3.4 `desktop_apps_count`

**Business Name**: Number of Desktop Apps Used  
**Definition**: Count of distinct desktop/web applications used to create notes.  
**Formula**: `COUNT(DISTINCT dimension_application_creation) WHERE platform = 'desktop'`  
**Unit**: Count (integer)  
**Interpretation**:

- **High values**: Diverse desktop tool usage
- **Zero**: No desktop app usage

**Use Cases**:

- Platform comparison: "Desktop users use more diverse tools than mobile users"
- Tool adoption: "JOSM and iD are the most common desktop tools"
- User preferences: "This user prefers desktop tools for note creation"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 3.5 `application_usage_trends`

**Business Name**: Application Usage Trends by Year  
**Definition**: JSON array containing application usage statistics grouped by year, showing how
application usage has changed over time.  
**Formula**: `json_agg(json_build_object('year', year, 'applications', app_data)) GROUP BY year`  
**Unit**: JSON array  
**Format**: `[{"year": 2023, "applications": [{"app_id": 1, "app_name": "iD", "count": 100, "pct": 45.5}, ...]}, ...]`  
**Interpretation**:
Shows how application preferences change over time

**Use Cases**:

- Trend analysis: "Mobile app usage increased from 20% (2020) to 60% (2024)"
- Technology adoption: "iD usage peaked in 2022, then declined"
- Platform shifts: "Desktop tools declining, mobile tools increasing"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 3.6 `version_adoption_rates`

**Business Name**: Version Adoption Rates by Year  
**Definition**: JSON array containing version adoption statistics grouped by year, showing which
application versions are being used over time.  
**Formula**: `json_agg(json_build_object('year', year, 'versions', version_data)) GROUP BY year`  
**Unit**: JSON array  
**Format**: `[{"year": 2023, "versions": [{"version": "2.20.0", "count": 50, "adoption_rate": 25.0}, ...]}, ...]`  
**Interpretation**:
Shows version adoption patterns and upgrade trends

**Use Cases**:

- Version tracking: "Version 2.20.0 adoption rate is 25% in 2023"
- Upgrade patterns: "Users are slow to adopt new versions"
- Technology trends: "Latest version adoption rate is increasing"

**Why it may be empty (or zero for all users)**: This metric is built from `dwh.facts.dimension_application_version`, which is only set when the **opening comment** of a note includes both an application match and a **version string** in the form `N.N` or `N.N.N` (e.g. "Opened with iD 2.19", "2.20.0"). Many clients do not send a version in the comment (e.g. "#organicmaps", "via StreetComplete"), so most facts have `dimension_application_version` NULL and `version_adoption_rates` remains an empty array `[]` for every user.  
**Source**: ETL sets version only when `action_comment = 'opened'`, an application is detected, and the comment matches regex `\d+\.\d+(\.\d+)?` (see `Staging_32_createStagingObjects.sql`, `Staging_34a_initialFactsLoadCreate_Parallel.sql`, `Staging_35a_initialFactsLoadExecute_Simple.sql`; `get_application_version_id`).  
**Diagnostic**: If `version_adoption_rates` is empty for all users, run `tests/sql/diagnose_version_adoption_rates.sql` against your DWH to see how many facts have `dimension_application_version` set; if that count is 0, no version data was extracted from your note comments.

**Available In**: `datamartusers`, `datamartcountries`

---

### 4. Content Quality Metrics

Metrics related to comment quality and engagement.

#### 4.1 `avg_comment_length`

**Business Name**: Average Comment Length  
**Definition**: Average number of characters in comments added to notes.  
**Formula**: `AVG(comment_length) WHERE comment_length IS NOT NULL`  
**Unit**: Characters (decimal, e.g., 150.5)  
**Interpretation**:

- **High values** (>200): Detailed explanations
- **Medium values** (50-200): Standard communication
- **Low values** (<50): Brief comments

**Use Cases**:

- Communication quality: "Average comment is 150 characters (detailed)"
- User behavior: "This user writes detailed comments (avg 200 chars)"
- Community standards: "Longer comments correlate with better resolution rates"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 4.2 `comments_with_url_count`

**Business Name**: Comments Containing Links  
**Definition**: Number of comments that contain URLs (web links).  
**Formula**: `COUNT(*) WHERE has_url = TRUE`  
**Unit**: Count (integer)  
**Interpretation**: URLs in comments often provide:

- Reference materials
- Evidence for the issue
- Related information
- External resources

**Use Cases**:

- Quality indicator: "30% of comments include reference links"
- User behavior: "This user frequently provides supporting links"
- Information sharing: "URLs help provide context for note issues"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 4.3 `comments_with_url_pct`

**Business Name**: Percentage of Comments with URLs  
**Definition**: Percentage of comments that contain URLs.  
**Formula**: `(COUNT(*) WHERE has_url = TRUE) / (COUNT(*) WHERE action_comment = 'commented') * 100`  
**Unit**:
Percentage (0-100, decimal)  
**Interpretation**:

- **High percentage** (>30%): Good use of external references
- **Low percentage** (<10%): Few external references

**Use Cases**:

- Quality measurement: "25% of comments include URLs (good reference usage)"
- Community comparison: "Country A uses URLs more than Country B"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 4.4 `comments_with_mention_count`

**Business Name**: Comments Mentioning Other Users  
**Definition**: Number of comments that mention other users (using @username format).  
**Formula**: `COUNT(*) WHERE has_mention = TRUE`  
**Unit**: Count (integer)  
**Interpretation**: Mentions indicate:

- Direct communication
- Collaboration
- Requesting help
- Acknowledging contributions

**Use Cases**:

- Collaboration measurement: "This note has 5 mentions (active collaboration)"
- User engagement: "This user frequently mentions others (collaborative)"
- Community interaction: "High mention count shows active discussion"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 4.5 `comments_with_mention_pct`

**Business Name**: Percentage of Comments with Mentions  
**Definition**: Percentage of comments that mention other users.  
**Formula**: `(COUNT(*) WHERE has_mention = TRUE) / (COUNT(*) WHERE action_comment = 'commented') * 100`  
**Unit**:
Percentage (0-100, decimal)  
**Interpretation**:

- **High percentage** (>20%): High collaboration
- **Low percentage** (<5%): Low collaboration

**Use Cases**:

- Collaboration measurement: "15% of comments mention other users"
- Community health: "High mention rate indicates active collaboration"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 4.6 `avg_comments_per_note`

**Business Name**: Average Comments per Note  
**Definition**: Average number of comments per note.  
**Formula**: `AVG(total_comments_on_note) WHERE action_comment = 'commented'`  
**Unit**: Count (decimal, e.g., 3.5)  
**Interpretation**:

- **High values** (>5): Active discussion, complex issues
- **Medium values** (2-5): Normal engagement
- **Low values** (<2): Minimal discussion

**Use Cases**:

- Engagement measurement: "Average 4 comments per note (active discussion)"
- Problem identification: "Notes with >10 comments may be controversial"
- Community activity: "High comment count shows active community"

**Available In**: `datamartusers`, `datamartcountries`

---

### 5. Temporal Pattern Metrics

Metrics related to when notes are created/resolved.

#### 5.1 `working_hours_of_week_opening`

**Business Name**: Activity by Hour of Week (Opening)  
**Definition**: JSON array showing note opening activity for each of the 168 hours of the week (7
days × 24 hours).  
**Formula**: `json_agg(action_count) GROUP BY action_dimension_id_hour_of_week ORDER BY hour_of_week`  
**Unit**:
JSON array (168 integers)  
**Format**: `[5, 3, 2, 1, 0, 0, 4, 8, 12, 15, ...]` (one value per hour)  
**Interpretation**: Shows when users are most active:

- **Weekdays 9-17**: Typical work hours
- **Evenings**: After-work activity
- **Weekends**: Leisure time activity
- **Night hours**: Different timezone or dedicated mappers

**Use Cases**:

- Activity patterns: "Users are most active Tuesday-Thursday 14:00-16:00"
- Timezone analysis: "Activity peaks at different hours (global community)"
- User behavior: "This user maps primarily on weekends"

**Available In**: `datamartusers`, `datamartcountries`  
**Note**: Hour 0 = Sunday 00:00, Hour 167 = Saturday 23:00

---

#### 5.2 `working_hours_of_week_commenting`

**Business Name**: Activity by Hour of Week (Commenting)  
**Definition**: JSON array showing comment activity for each hour of the week.  
**Formula**: Similar to `working_hours_of_week_opening` but for comments  
**Unit**: JSON array (168 integers)  
**Interpretation**: Shows when users engage in discussions

**Use Cases**:

- Discussion patterns: "Comments peak during weekday afternoons"
- Engagement analysis: "Users comment more on weekends"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 5.3 `working_hours_of_week_closing`

**Business Name**: Activity by Hour of Week (Closing)  
**Definition**: JSON array showing note closing activity for each hour of the week.  
**Formula**: Similar to `working_hours_of_week_opening` but for closures  
**Unit**: JSON array (168 integers)  
**Interpretation**: Shows when users resolve notes

**Use Cases**:

- Resolution patterns: "Notes are closed primarily during work hours"
- Productivity analysis: "Resolution activity peaks on weekday mornings"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 5.4 `last_year_activity`

**Business Name**: GitHub-Style Activity Heatmap  
**Definition**: String representation of activity over the last year (371 characters, one per
day).  
**Formula**: Character encoding of daily activity counts  
**Unit**: String (371 characters)  
**Format**: Each character represents one day's activity level (encoded)  
**Interpretation**: Visual representation similar to GitHub contribution graph:

- Each character represents one day
- Character intensity shows activity level
- Patterns show consistency and engagement

**Use Cases**:

- Visual activity display: "Show activity heatmap on user profile"
- Consistency measurement: "This user maps consistently (no gaps)"
- Trend visualization: "Activity increased in recent months"

**Available In**: `datamartusers`, `datamartcountries`  
**Note**: 371 characters = 365 days + 6 characters for encoding

---

#### 5.5 `dates_most_open`

**Business Name**: Peak Opening Dates  
**Definition**: JSON array of dates when the most notes were opened.  
**Formula**: `json_agg(date ORDER BY count DESC LIMIT 10)`  
**Unit**: JSON array of date strings  
**Format**: `["2024-01-15", "2024-03-22", "2024-06-10", ...]`  
**Interpretation**: Shows peak activity dates (may indicate events, campaigns, or special dates)

**Use Cases**:

- Event identification: "Peak activity on mapathon dates"
- Campaign tracking: "High activity during #MissingMaps campaign"
- Pattern analysis: "Activity spikes on first Saturday of each month"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 5.6 `dates_most_closed`

**Business Name**: Peak Closing Dates  
**Definition**: JSON array of dates when the most notes were closed.  
**Formula**: Similar to `dates_most_open` but for closures  
**Unit**: JSON array of date strings  
**Interpretation**: Shows peak resolution dates

**Use Cases**:

- Resolution patterns: "Most resolutions occur on weekends"
- Productivity analysis: "Resolution spikes after mapathons"

**Available In**: `datamartusers`, `datamartcountries`

---

### 6. Geographic Pattern Metrics

Metrics related to where notes are created/resolved.

#### 6.1 `countries_open_notes` (User Datamart)

**Business Name**: User's Geographic Contribution Areas  
**Definition**: JSON array of country IDs where a user has opened notes.  
**Formula**: `json_agg(DISTINCT dimension_id_country) WHERE action_comment = 'opened'`  
**Unit**: JSON array of country IDs  
**Format**: `[1, 5, 12, 23, 45]`  
**Interpretation**:

- **Single country**: Local mapper
- **Multiple countries**: Traveling mapper or global contributor
- **Many countries**: Very active global contributor

**Use Cases**:

- User profile: "This user contributes in 5 countries"
- Geographic diversity: "This user maps globally, not just locally"
- Contribution scope: "User focuses on specific region"

**Available In**: `datamartusers` only

---

#### 6.2 `countries_solving_notes` (User Datamart)

**Business Name**: Countries Where User Resolves Notes  
**Definition**: JSON array of country IDs where a user has closed notes.  
**Formula**: `json_agg(DISTINCT dimension_id_country) WHERE action_comment = 'closed'`  
**Unit**: JSON array of country IDs  
**Interpretation**: Shows geographic scope of resolution activity

**Use Cases**:

- Resolution scope: "This user resolves notes in 3 countries"
- Global contribution: "User helps resolve notes globally"

**Available In**: `datamartusers` only

---

#### 6.3 `users_open_notes` (Country Datamart)

**Business Name**: Contributors Opening Notes  
**Definition**: JSON array of user IDs who have opened notes in this country.  
**Formula**: `json_agg(DISTINCT action_dimension_id_user) WHERE action_comment = 'opened'`  
**Unit**: JSON array of user IDs  
**Interpretation**: Shows community size and diversity

**Use Cases**:

- Community size: "500 users have created notes in this country"
- Contributor diversity: "Large and diverse contributor base"

**Available In**: `datamartcountries` only

---

#### 6.4 `users_solving_notes` (Country Datamart)

**Business Name**: Contributors Resolving Notes  
**Definition**: JSON array of user IDs who have closed notes in this country.  
**Formula**: `json_agg(DISTINCT action_dimension_id_user) WHERE action_comment = 'closed'`  
**Unit**: JSON array of user IDs  
**Interpretation**: Shows resolver community size

**Use Cases**:

- Resolver community: "200 users actively resolve notes in this country"
- Community health: "Large resolver community indicates healthy ecosystem"

**Available In**: `datamartcountries` only

---

#### 6.5 `ranking_countries_opening_YYYY` (User Datamart)

**Business Name**: Top Countries by Activity (Year YYYY)  
**Definition**: JSON array of top countries ranked by note opening activity for a specific year.  
**Formula**: `json_agg(json_build_object('country_id', country_id, 'count', count, 'rank', rank) ORDER BY count DESC LIMIT 10)`  
**Unit**:
JSON array of objects  
**Format**: `[{"country_id": 1, "count": 150, "rank": 1}, {"country_id": 5, "count": 120, "rank": 2}, ...]`  
**Interpretation**:
Shows which countries user is most active in for that year

**Use Cases**:

- Geographic focus: "User's top country in 2023 was Colombia"
- Trend analysis: "User's activity shifted from Country A to Country B"

**Available In**: `datamartusers` only  
**Note**: One column per year (2013, 2014, ..., 2024, etc.)

---

#### 6.6 `ranking_users_opening_YYYY` (Country Datamart)

**Business Name**: Top Users by Activity (Year YYYY)  
**Definition**: JSON array of top users ranked by note opening activity for a specific year.  
**Formula**: Similar to `ranking_countries_opening_YYYY` but for users  
**Unit**: JSON array of objects  
**Interpretation**: Shows top contributors for that year

**Use Cases**:

- Leaderboards: "Top 10 users by note activity in 2023"
- Recognition: "Highlight top contributors for the year"

**Available In**: `datamartcountries` only  
**Note**: One column per year (2013, 2014, ..., 2024, etc.)

---

#### 6.7 `ranking_users_closing_YYYY` (Country Datamart)

**Business Name**: Top Resolvers by Activity (Year YYYY)  
**Definition**: JSON array of top users ranked by note closing activity for a specific year.  
**Formula**: Similar to `ranking_users_opening_YYYY` but for closures  
**Unit**: JSON array of objects  
**Interpretation**: Shows top resolvers for that year

**Use Cases**:

- Resolver leaderboards: "Top 10 resolvers in 2023"
- Recognition: "Acknowledge top resolvers"

**Available In**: `datamartcountries` only

---

### 7. Community Health Metrics

Metrics related to backlog, active notes, and community activity.

#### 7.1 `active_notes_count`

**Business Name**: Currently Open Notes  
**Definition**: Number of notes that are currently open (not yet closed).  
**Formula**: `COUNT(DISTINCT id_note) WHERE action_comment = 'opened' AND id_note NOT IN (SELECT DISTINCT id_note WHERE action_comment = 'closed')`  
**Unit**:
Count (integer)  
**Interpretation**:

- **High values**: Large active backlog
- **Low values**: Most notes resolved

**Use Cases**:

- Backlog measurement: "500 notes currently open"
- Community health: "Active notes count indicates current workload"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 7.2 `notes_backlog_size`

**Business Name**: Notes Backlog Size  
**Definition**: Number of notes opened but not yet resolved. Same as `active_notes_count` but with
different semantic meaning.  
**Formula**: Same as `active_notes_count`  
**Unit**: Count (integer)  
**Interpretation**:

- **High values**: Large backlog, may need community support
- **Low values**: Good resolution coverage

**Use Cases**:

- Backlog tracking: "Backlog size is 1,000 notes"
- Resource planning: "Large backlog indicates need for more resolvers"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 7.3 `notes_age_distribution`

**Business Name**: Notes Age Distribution  
**Definition**: JSON object showing distribution of note ages in buckets.  
**Formula**: `json_build_object('0_7_days', count_0_7, '8_30_days', count_8_30, '31_90_days', count_31_90, '90_plus_days', count_90_plus)`  
**Unit**:
JSON object  
**Format**: `{"0_7_days": 100, "8_30_days": 50, "31_90_days": 25, "90_plus_days": 10}`  
**Interpretation**:

- **High 0-7 days**: Recent activity, good responsiveness
- **High 90+ days**: Old backlog, may need attention

**Use Cases**:

- Backlog analysis: "Most notes are recent (0-7 days)"
- Problem identification: "Many notes are 90+ days old (stale backlog)"
- Community health: "Age distribution shows healthy resolution patterns"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 7.4 `notes_created_last_30_days`

**Business Name**: Notes Created in Last 30 Days  
**Definition**: Number of notes opened in the last 30 days.  
**Formula**: `COUNT(*) WHERE action_comment = 'opened' AND action_at >= CURRENT_DATE - INTERVAL '30 days'`  
**Unit**:
Count (integer)  
**Interpretation**: Shows recent activity level

**Use Cases**:

- Recent activity: "50 notes created in last 30 days"
- Trend analysis: "Activity increased 20% in last month"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 7.5 `notes_resolved_last_30_days`

**Business Name**: Notes Resolved in Last 30 Days  
**Definition**: Number of notes closed in the last 30 days.  
**Formula**: `COUNT(*) WHERE action_comment = 'closed' AND action_at >= CURRENT_DATE - INTERVAL '30 days'`  
**Unit**:
Count (integer)  
**Interpretation**: Shows recent resolution activity

**Use Cases**:

- Recent resolution: "40 notes resolved in last 30 days"
- Productivity: "Resolution activity is steady"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 7.6 `notes_health_score` (Countries only)

**Business Name**: Overall Notes Health Score  
**Definition**: Composite score (0-100) that measures the overall health of notes in a country,
based on resolution rate, backlog size, and recent activity.  
**Formula**: `(resolution_rate * 0.4) + ((100 - backlog_ratio) * 0.3) + (recent_activity_score * 0.3)`  
**Unit**:
Score (0-100, decimal)  
**Interpretation**:

- **Excellent** (80-100): High resolution rate, low backlog, active community
- **Good** (60-80): Decent resolution rate, manageable backlog
- **Fair** (40-60): Moderate issues, some backlog
- **Poor** (<40): Low resolution rate, high backlog, inactive community

**Use Cases**:

- Community health monitoring: "Country health score is 75 (good)"
- Comparison: "Country A (85) is healthier than Country B (45)"
- Trend analysis: "Health score improved from 50 to 75 this year"

**Available In**: `datamartcountries` only

---

#### 7.7 `new_vs_resolved_ratio` (Countries only)

**Business Name**: New vs Resolved Notes Ratio  
**Definition**: Ratio of new notes created vs resolved notes in the last 30 days.  
**Formula**: `notes_created_last_30_days / notes_resolved_last_30_days`  
**Unit**: Ratio (decimal, can be 999.99 for infinite when no resolutions)  
**Interpretation**:

- **< 1.0**: More notes resolved than created (backlog shrinking)
- **= 1.0**: Balanced (same created as resolved)
- **> 1.0**: More notes created than resolved (backlog growing)
- **999.99**: No resolutions (infinite ratio)

**Use Cases**:

- Backlog trend: "Ratio is 0.8 (backlog shrinking)"
- Problem identification: "Ratio is 2.5 (backlog growing rapidly)"
- Community balance: "Ratio is 1.0 (balanced activity)"

**Available In**: `datamartcountries` only

---

### 8. User Behavior Metrics

Metrics related to user behavior patterns, responsiveness, and collaboration.

#### 8.1 `user_response_time` (Users only)

**Business Name**: Average User Response Time  
**Definition**: Average time in days from when a user opens a note to when they add their first
comment.  
**Formula**: `AVG(EXTRACT(EPOCH FROM (first_comment_time - open_time)) / 86400.0)`  
**Unit**: Days (decimal, e.g., 2.5 days)  
**Interpretation**:

- **Low values** (<1 day): Very responsive user
- **Medium values** (1-3 days): Responsive user
- **High values** (>3 days): Less responsive user

**Use Cases**:

- User responsiveness: "This user responds within 1 day on average"
- Community engagement: "Average response time is 2 days"
- User comparison: "User A (0.5 days) is more responsive than User B (5 days)"

**Available In**: `datamartusers` only

---

#### 8.2 `days_since_last_action` (Users only)

**Business Name**: Days Since Last Action  
**Definition**: Number of days since the user last performed any action (opened, commented, closed,
or reopened a note).  
**Formula**: `CURRENT_DATE - MAX(action_at)`  
**Unit**: Days (integer)  
**Interpretation**:

- **0-7 days**: Very active user
- **8-30 days**: Active user
- **31-90 days**: Inactive user
- **90+ days**: Very inactive or retired user

**Use Cases**:

- User activity status: "This user was active 5 days ago"
- Inactive user detection: "User hasn't been active in 120 days"
- Community engagement: "Most users were active in the last 30 days"

**Available In**: `datamartusers` only

---

#### 8.3 `collaboration_patterns` (Users only)

**Business Name**: User Collaboration Patterns  
**Definition**: JSON object containing metrics about user collaboration, including mentions given,
mentions received, replies, and a collaboration score.  
**Formula**: `json_build_object('mentions_given', mentions_given, 'mentions_received', mentions_received, 'replies_count', replies_count, 'collaboration_score', total_score)`  
**Unit**:
JSON object  
**Format**: `{"mentions_given": 50, "mentions_received": 30, "replies_count": 25, "collaboration_score": 105}`  
**Interpretation**:

- **High collaboration_score**: Very collaborative user
- **High mentions_given**: User actively engages with others
- **High mentions_received**: User is frequently mentioned by others
- **High replies_count**: User actively responds to discussions

**Use Cases**:

- Collaboration measurement: "This user has a collaboration score of 105"
- User engagement: "This user mentions others frequently (50 mentions given)"
- Community recognition: "This user is frequently mentioned (30 mentions received)"

**Available In**: `datamartusers` only

---

#### 8.4 `notes_opened_but_not_closed_by_user` (Users only)

**Business Name**: Notes Opened But Not Closed By User  
**Definition**: Number of notes opened by this user that were never closed by this same user (either
closed by others or still open).  
**Formula**: `COUNT(DISTINCT id_note) WHERE opened_dimension_id_user = user_id AND action_comment = 'opened' AND NOT EXISTS (SELECT 1 WHERE closed_dimension_id_user = user_id AND action_comment = 'closed')`  
**Unit**:
Count (integer)  
**Interpretation**:

- **High values** (>50% of opened notes): User reports problems but depends on others to resolve
  them
- **Low values** (<20% of opened notes): User resolves their own reports
- **0**: User always closes their own notes, or never opens notes

**Use Cases**:

- User behavior analysis: "This user opened 100 notes but only closed 20 of them"
- Dependency measurement: "60% of this user's opened notes were closed by others"
- Self-sufficiency indicator: "User A closes 80% of their own notes vs User B closes 20%"
- Community collaboration: "This user reports problems and the community helps resolve them"

**Available In**: `datamartusers` only  
**Note**: This metric complements `notes_resolved_count` and `notes_still_open_count` to provide a
complete picture of user behavior. The relationship is:
`history_whole_open = notes_resolved_count + notes_opened_but_not_closed_by_user + notes_still_open_count`

- Community engagement: "User frequently mentions others (50 mentions given)"
- Social patterns: "User is well-connected (30 mentions received)"

**Available In**: `datamartusers` only

---

### 9. Hashtag Metrics

Metrics related to hashtag usage in notes.

#### 8.1 `hashtags`

**Business Name**: Hashtags Used  
**Definition**: JSON array of hashtags used in notes.  
**Formula**: `json_agg(DISTINCT dimension_hashtag_id)`  
**Unit**: JSON array of hashtag IDs  
**Format**: `[1, 5, 12, 23]`  
**Interpretation**: Shows hashtag diversity

**Use Cases**:

- Campaign tracking: "User participates in #MissingMaps campaign"
- Organization: "Country uses diverse hashtags for organization"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 8.2 `hashtags_opening`

**Business Name**: Top Hashtags in Opening Actions  
**Definition**: JSON array of top hashtags used when opening notes.  
**Formula**: `json_agg(json_build_object('hashtag_id', hashtag_id, 'count', count) ORDER BY count DESC LIMIT 10)`  
**Unit**:
JSON array of objects  
**Format**: `[{"hashtag_id": 5, "count": 150}, {"hashtag_id": 12, "count": 120}, ...]`  
**Interpretation**: Shows most popular hashtags for note creation

**Use Cases**:

- Campaign analysis: "#MissingMaps is most used opening hashtag"
- Organization patterns: "Users organize notes by campaign hashtags"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 8.3 `hashtags_resolution`

**Business Name**: Top Hashtags in Resolution Actions  
**Definition**: JSON array of top hashtags used when closing notes.  
**Formula**: Similar to `hashtags_opening` but for closing actions  
**Unit**: JSON array of objects  
**Interpretation**: Shows hashtags used in resolutions

**Use Cases**:

- Resolution patterns: "#Fixed is most common resolution hashtag"
- Campaign tracking: "Resolution hashtags show campaign completion"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 8.4 `hashtags_comments`

**Business Name**: Top Hashtags in Comments  
**Definition**: JSON array of top hashtags used in comment actions.  
**Formula**: Similar to `hashtags_opening` but for comments  
**Unit**: JSON array of objects  
**Interpretation**: Shows hashtags used in discussions

**Use Cases**:

- Discussion patterns: "Hashtags used in comments show topic organization"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 8.5 `favorite_opening_hashtag` / `top_opening_hashtag`

**Business Name**: Most Used Opening Hashtag  
**Definition**: The hashtag most frequently used when opening notes.  
**Formula**: `MODE() WITHIN GROUP (ORDER BY dimension_hashtag_id) WHERE used_in_action = 'opened'`  
**Unit**: Hashtag name (VARCHAR)  
**Interpretation**: Shows primary campaign or organization method

**Use Cases**:

- Campaign identification: "User's favorite hashtag is #MissingMaps"
- Organization: "Country primarily uses #Mapathon2024"

**Available In**: `datamartusers` (favorite_opening_hashtag), `datamartcountries`
(top_opening_hashtag)

---

#### 8.6 `favorite_resolution_hashtag` / `top_resolution_hashtag`

**Business Name**: Most Used Resolution Hashtag  
**Definition**: The hashtag most frequently used when closing notes.  
**Formula**: Similar to `favorite_opening_hashtag` but for closures  
**Unit**: Hashtag name (VARCHAR)  
**Interpretation**: Shows primary resolution hashtag

**Use Cases**:

- Resolution patterns: "Most resolutions use #Fixed hashtag"

**Available In**: `datamartusers` (favorite_resolution_hashtag), `datamartcountries`
(top_resolution_hashtag)

---

#### 8.7 `opening_hashtag_count`

**Business Name**: Total Opening Hashtags Used  
**Definition**: Total count of hashtags used in opening actions.  
**Formula**: `COUNT(*) WHERE used_in_action = 'opened'`  
**Unit**: Count (integer)  
**Interpretation**: Shows hashtag usage frequency

**Use Cases**:

- Usage measurement: "User has used opening hashtags 500 times"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 8.8 `resolution_hashtag_count`

**Business Name**: Total Resolution Hashtags Used  
**Definition**: Total count of hashtags used in closing actions.  
**Formula**: `COUNT(*) WHERE used_in_action = 'closed'`  
**Unit**: Count (integer)  
**Interpretation**: Shows resolution hashtag usage

**Use Cases**:

- Usage measurement: "Country uses resolution hashtags frequently"

**Available In**: `datamartusers`, `datamartcountries`

---

### 10. First/Last Action Metrics

Metrics tracking the first and most recent actions.

#### 9.1 `date_starting_creating_notes`

**Business Name**: First Note Creation Date  
**Definition**: Date when the first note was opened by user/country.  
**Formula**: `MIN(action_dimension_id_date) WHERE action_comment = 'opened'`  
**Unit**: Date  
**Interpretation**: Shows when user/country started contributing

**Use Cases**:

- User history: "User started creating notes in 2015"
- Country history: "Country has notes since 2013"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 9.2 `date_starting_solving_notes`

**Business Name**: First Note Resolution Date  
**Definition**: Date when the first note was closed by user/country.  
**Formula**: `MIN(action_dimension_id_date) WHERE action_comment = 'closed'`  
**Unit**: Date  
**Interpretation**: Shows when user/country started resolving notes

**Use Cases**:

- Resolution history: "User started resolving notes in 2016"
- Community evolution: "Country started resolving notes in 2014"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 9.3 `first_open_note_id`

**Business Name**: First Note ID Created  
**Definition**: OSM note ID of the first note opened.  
**Formula**: `MIN(id_note) WHERE action_comment = 'opened'`  
**Unit**: Note ID (integer)  
**Interpretation**: Reference to the first note

**Use Cases**:

- Historical reference: "Link to user's first note"
- Milestone tracking: "Celebrate first note anniversary"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 9.4 `first_commented_note_id`, `first_closed_note_id`, `first_reopened_note_id`

**Business Name**: First Note ID for Action Type  
**Definition**: OSM note ID of the first note for each action type.  
**Formula**: `MIN(id_note) WHERE action_comment = 'commented'` (and similar for closed, reopened)  
**Unit**: Note ID (integer)  
**Interpretation**: Reference to first action of each type

**Available In**: `datamartusers`, `datamartcountries`

---

#### 9.5 `lastest_open_note_id` (Note: "lastest" is the column name)

**Business Name**: Most Recent Note ID Created  
**Definition**: OSM note ID of the most recent note opened.  
**Formula**: `MAX(id_note) WHERE action_comment = 'opened'`  
**Unit**: Note ID (integer)  
**Interpretation**: Reference to the most recent note

**Use Cases**:

- Recent activity: "Link to user's most recent note"
- Activity verification: "User created a note yesterday"

**Available In**: `datamartusers`, `datamartcountries`

---

#### 9.6 `lastest_commented_note_id`, `lastest_closed_note_id`, `lastest_reopened_note_id`

**Business Name**: Most Recent Note ID for Action Type  
**Definition**: OSM note ID of the most recent note for each action type.  
**Formula**: `MAX(id_note) WHERE action_comment = 'commented'` (and similar)  
**Unit**: Note ID (integer)  
**Interpretation**: Reference to most recent action of each type

**Available In**: `datamartusers`, `datamartcountries`

---

### 11. Current Period Metrics

Metrics for current time periods (month, day).

#### 10.1 `countries_open_notes_current_month` (User Datamart)

**Business Name**: Countries This Month  
**Definition**: JSON array of countries where user opened notes in current month.  
**Formula**: `json_agg(DISTINCT dimension_id_country) WHERE action_comment = 'opened' AND action_dimension_id_date IN (current_month_dates)`  
**Unit**:
JSON array  
**Interpretation**: Shows recent geographic activity

**Available In**: `datamartusers` only

---

#### 10.2 `countries_open_notes_current_day` (User Datamart)

**Business Name**: Countries Today  
**Definition**: JSON array of countries where user opened notes today.  
**Formula**: Similar to `countries_open_notes_current_month` but for today  
**Unit**: JSON array  
**Interpretation**: Shows today's geographic activity

**Available In**: `datamartusers` only

---

#### 10.3 `users_open_notes_current_month` (Country Datamart)

**Business Name**: Contributors This Month  
**Definition**: JSON array of users who opened notes in current month.  
**Formula**: `json_agg(DISTINCT action_dimension_id_user) WHERE action_comment = 'opened' AND action_dimension_id_date IN (current_month_dates)`  
**Unit**:
JSON array  
**Interpretation**: Shows recent contributors

**Available In**: `datamartcountries` only

---

#### 10.4 `users_open_notes_current_day` (Country Datamart)

**Business Name**: Contributors Today  
**Definition**: JSON array of users who opened notes today.  
**Formula**: Similar to `users_open_notes_current_month` but for today  
**Unit**: JSON array  
**Interpretation**: Shows today's contributors

**Available In**: `datamartcountries` only

---

### 12. User Classification Metrics

#### 11.1 `id_contributor_type`

**Business Name**: Contributor Type Classification  
**Definition**: Classification of user based on activity level and patterns.  
**Formula**: Classification algorithm based on:

- Total actions
- Activity consistency
- Time since first action
- Automation patterns

**Unit**: Integer (FK to `dwh.contributor_types`)  
**Types** (23 types available):

- **Normal Notero** (1): Regular contributor
- **Just starting notero** (2): New contributor
- **Newbie Notero** (3): Beginner
- **All-time notero** (4): Long-term contributor
- **Hit-and-run notero** (5): One-time contributor
- **Junior notero** (6): Developing contributor
- **Inactive notero** (7): Currently inactive
- **Retired notero** (8): Former contributor
- **Forgotten notero** (9): Very old account
- **Sporadic notero** (10): Irregular contributor
- **Start closing notero** (11): Beginning to resolve
- **Casual notero** (12): Occasional contributor
- **Power closing notero** (13): High-activity resolver
- **Power notero** (14): High-activity contributor
- **Crazy closing notero** (15): Very high-activity resolver
- **Crazy notero** (16): Very high-activity contributor
- **Addicted closing notero** (17): Extremely active resolver
- **Addicted notero** (18): Extremely active contributor
- **Epic closing notero** (19): Exceptional resolver
- **Epic notero** (20): Exceptional contributor
- **Bot closing notero** (21): Automated resolver
- **Robot notero** (22): Automated contributor
- **OoM Exception notero** (23): Exceptionally high activity

**Use Cases**:

- User recognition: "This user is classified as Power Contributor"
- Community analysis: "10% of users are Power Contributors"
- Mentorship: "Power Contributors can mentor Normal Contributors"

**Available In**: `datamartusers` only

---

## Metric Summary Table

### User Datamart Metrics (78+ metrics)

| Category               | Metric Count | Examples                                                                           |
| ---------------------- | ------------ | ---------------------------------------------------------------------------------- |
| Historical Counts      | 30+          | `history_whole_open`, `history_year_open`, `history_2013_open`, etc.               |
| Resolution Metrics     | 7            | `avg_days_to_resolution`, `resolution_rate`, `resolution_by_year`, etc.            |
| Application Statistics | 4            | `applications_used`, `most_used_application_id`, `mobile_apps_count`, etc.         |
| Content Quality        | 5            | `avg_comment_length`, `comments_with_url_pct`, `avg_comments_per_note`, etc.       |
| Temporal Patterns      | 5            | `working_hours_of_week_opening`, `last_year_activity`, `dates_most_open`, etc.     |
| Geographic Patterns    | 15+          | `countries_open_notes`, `ranking_countries_opening_2013`, etc.                     |
| Community Health       | 5            | `active_notes_count`, `notes_backlog_size`, `notes_age_distribution`, etc.         |
| Hashtag Metrics        | 8            | `hashtags`, `hashtags_opening`, `favorite_opening_hashtag`, etc.                   |
| First/Last Actions     | 8            | `date_starting_creating_notes`, `first_open_note_id`, `lastest_open_note_id`, etc. |
| User Classification    | 1            | `id_contributor_type`                                                              |

**Total**: 78+ metrics per user (includes `notes_opened_but_not_closed_by_user`)

### Country Datamart Metrics (77+ metrics)

| Category               | Metric Count | Examples                                               |
| ---------------------- | ------------ | ------------------------------------------------------ |
| Historical Counts      | 30+          | Same as user datamart                                  |
| Resolution Metrics     | 7            | Same as user datamart                                  |
| Application Statistics | 4            | Same as user datamart                                  |
| Content Quality        | 5            | Same as user datamart                                  |
| Temporal Patterns      | 5            | Same as user datamart                                  |
| Geographic Patterns    | 15+          | `users_open_notes`, `ranking_users_opening_2013`, etc. |
| Community Health       | 5            | Same as user datamart                                  |
| Hashtag Metrics        | 8            | Same as user datamart                                  |
| First/Last Actions     | 8            | Same as user datamart                                  |

**Total**: 77+ metrics per country

---

## Metric Calculation Details

### How Metrics Are Calculated

**Source Data**: All metrics are calculated from `dwh.facts` table aggregated by:

- **User Datamart**: Grouped by `action_dimension_id_user`
- **Country Datamart**: Grouped by `dimension_id_country`

**Calculation Process**:

1. Read facts from `dwh.facts`
2. Filter by user/country
3. Aggregate by time period (whole, year, month, day)
4. Calculate derived metrics (averages, percentages, distributions)
5. Store in datamart table

**Update Frequency**:

- **Incremental**: Only modified entities updated
- **Full**: All entities recalculated (rare, for schema changes)

---

## Metric Interpretation Guide

### Understanding Metric Values

**Count Metrics** (integers):

- **High**: Above average for user/country type
- **Medium**: Average for user/country type
- **Low**: Below average

**Rate Metrics** (percentages):

- **Excellent**: Top 25% of values
- **Good**: 25-75th percentile
- **Needs Improvement**: Bottom 25%

**Time Metrics** (days):

- **Fast**: Below median
- **Average**: Around median
- **Slow**: Above median

### Comparing Metrics

**User vs Country**:

- User metrics show individual contribution
- Country metrics show community performance

**Time Periods**:

- Compare whole history vs current year to see trends
- Compare year vs month to see recent activity

**Ratios**:

- Resolution rate = closed / opened
- Comment rate = commented / opened
- Reopen rate = reopened / opened

---

## Related Documentation

- **[Business Glossary](Business_Glossary.md)**: Core business terms and key metrics
- **[Data Dictionary](DWH_Star_Schema_Data_Dictionary.md)**: Technical column definitions
- **[Data Lineage](Data_Lineage.md)**: How metrics are calculated from source data
- **[Dashboard Analysis](Dashboard_Analysis.md)**: Available metrics for dashboards

---

## References

- [DAMA DMBOK - Metric Definitions](https://www.dama.org/)
- [Kimball Group - Business Metrics](https://www.kimballgroup.com/)
- [OSM Notes Documentation](https://wiki.openstreetmap.org/wiki/Notes)
