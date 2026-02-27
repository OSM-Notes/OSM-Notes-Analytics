---
title: "Dashboard Analysis: OSM Notes Analytics"
description:
  "This document analyzes the data available in the OSM Notes Analytics data warehouse (star schema)"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Dashboard Analysis: OSM Notes Analytics

## Data Mapping Between Star Schema and Datamarts

## 📊 Executive Summary

This document analyzes the data available in the OSM Notes Analytics data warehouse (star schema)
versus what's exposed through the datamarts. It identifies gaps, recommendations for dashboard
implementation, and documents the enhancements implemented in October 2025.

### Recent Enhancements (October 2025)

The datamarts were enhanced with 21 new metrics across 4 categories:

- **Resolution Metrics**: Average/median days to resolution, resolution rates
- **Application Statistics**: Usage patterns, mobile vs desktop apps
- **Content Quality Metrics**: Comment analysis, URLs, mentions
- **Community Health Metrics**: Active notes, backlog, age distribution, recent activity

---

## 🏗️ Star Schema (dwh.facts) - Full Data Available

### Available Dimensions

#### 1. **Time Dimensions**

- `dimension_days`: Date attributes (year, month, day, ISO week, quarter, day name, weekend flags,
  end-of-period flags)
- `dimension_time_of_week`: Hour-of-week (0-167), day-of-week (1-7), hour-of-day (0-23), period
  (Morning/Afternoon/Evening/Night)
- `dimension_timezones`: For local time analysis
- `dimension_seasons`: Seasonal analysis based on date and latitude

#### 2. **Geographic Dimensions**

- `dimension_countries`: Country info (id, names in 3 languages, ISO codes, region)
- `dimension_regions`: Geographic regions
- `dimension_continents`: Continental grouping

#### 3. **User Dimensions**

- `dimension_users`: User info with SCD2 support (username changes tracked)

#### 4. **Application Dimensions**

- `dimension_applications`: Apps used to create notes (JOSM, iD, MapComplete, etc.)
- `dimension_application_versions`: Version tracking

#### 5. **Content Dimensions**

- `dimension_hashtags`: Hashtags found in notes
- `fact_hashtags`: Bridge table (many-to-many relationship)

### Available Fact Metrics

#### Action Metrics

- `action_comment`: Type (opened, closed, reopened, commented, hidden)
- `action_at`: Timestamp when action occurred
- `total_actions_on_note`: Total actions up to this point
- `total_comments_on_note`: Total comments up to this point
- `total_reopenings_count`: Total reopenings up to this point

#### Resolution Metrics

- `days_to_resolution`: Days from first open to most recent close
- `days_to_resolution_active`: Sum of days while note was open (handles reopens)
- `days_to_resolution_from_reopen`: Days from last reopen to most recent close
- `recent_opened_dimension_id_date`: Most recent open/reopen date

#### Comment Content Metrics

- `comment_length`: Length of comment text
- `has_url`: Boolean if comment contains URL
- `has_mention`: Boolean if comment mentions another user
- `hashtag_number`: Count of hashtags in the text
- Hashtag details via `fact_hashtags` bridge table

#### Geographic & Temporal Context

- `action_timezone_id`: Local timezone for the action
- `local_action_dimension_id_date`: Local date ID
- `local_action_dimension_id_hour_of_week`: Local hour-of-week
- `action_dimension_id_season`: Season (Northern/Southern hemisphere)

#### Open/Close Tracking

- `opened_dimension_id_date`: Date when note was created
- `opened_dimension_id_hour_of_week`: Hour-of-week when created
- `opened_dimension_id_user`: User who created the note
- `closed_dimension_id_date`: Date when note was closed
- `closed_dimension_id_hour_of_week`: Hour-of-week when closed
- `closed_dimension_id_user`: User who closed the note

#### Application Tracking

- `dimension_application_creation`: Application used to create note
- `dimension_application_version`: Version of application

---

## 📦 Datamarts - Precomputed Data

### datamartCountries - Country-Level Aggregates

#### ✅ Available Metrics

**Historical Counts** (whole, year, month, day):

- `history_whole_open/commented/closed/closed_with_comment/reopened`
- `history_year_open/commented/closed/closed_with_comment/reopened`
- `history_month_open/commented/closed/closed_with_comment/reopened`
- `history_day_open/commented/closed/closed_with_comment/reopened`
- Per-year columns (2013-2024+)

**Temporal Patterns**:

- `last_year_activity`: GitHub-style activity heatmap (371 chars)
- `working_hours_of_week_opening/commenting/closing`: JSON array of activity by hour-of-week
- `dates_most_open/closed`: JSON array of peak activity dates

**Contributors**:

- `users_open_notes`: JSON array of users opening notes
- `users_solving_notes`: JSON array of users closing notes
- `users_open_notes_current_month/day`: Current period contributors
- `users_solving_notes_current_month/day`: Current period contributors
- `ranking_users_opening_2013`: Top users by year
- `ranking_users_closing_2013`: Top users by year

**Content**:

- `hashtags`: JSON array of hashtags used

**Firsts/Lasts**:

- `date_starting_creating_notes`: Oldest opened note
- `date_starting_solving_notes`: Oldest closed note
- `first_open_note_id`: First note ID
- `latest_open_note_id`: Most recent note ID
- Same for commented/closed/reopened

### datamartUsers - User-Level Aggregates

#### ✅ Available Metrics

**Historical Counts** (whole, year, month, day):

- `history_whole_open/commented/closed/closed_with_comment/reopened`
- `history_year_open/commented/closed/closed_with_comment/reopened`
- `history_month_open/commented/closed/closed_with_comment/reopened`
- `history_day_open/commented/closed/closed_with_comment/reopened`
- Per-year columns (2013-2024+)

**Geographic Patterns**:

- `countries_open_notes`: JSON array of countries where user opens notes
- `countries_solving_notes`: JSON array of countries where user closes notes
- `countries_open_notes_current_month/day`: Current period countries
- `ranking_countries_opening_2013`: Top countries by year

**Temporal Patterns**:

- `last_year_activity`: GitHub-style activity heatmap
- `working_hours_of_week_opening/commenting/closing`: JSON array

**Content**:

- `hashtags`: JSON array of hashtags used

**Firsts/Lasts**: Same as countries

**User Classification**:

- `id_contributor_type`: Contributor type classification (Normal, Power, Epic, Bot, etc.)
- Link to `badges` table
- Link to `badges_per_users` table

---

## 🎯 Dashboard-Ready Data Analysis

### ✅ EXCELLENT for Dashboard (Already in Datamarts)

1. **Activity Trends (Temporal)** ⭐⭐⭐⭐⭐
   - ✅ Monthly/Yearly activity counts
   - ✅ GitHub-style activity heatmaps
   - ✅ Working hours patterns (hour-of-week)
   - ✅ Peak activity dates

2. **Geographic Analysis** ⭐⭐⭐⭐⭐
   - ✅ Country-level aggregates
   - ✅ User country activity lists
   - ✅ Rankings by country

3. **User Engagement** ⭐⭐⭐⭐⭐
   - ✅ Contributor types (Normal/Power/Epic/Bot)
   - ✅ User rankings by country
   - ✅ Historical counts per user
   - ✅ Badges system

4. **Content Analysis** ⭐⭐⭐⭐
   - ✅ Hashtag lists per country/user
   - ✅ Note type counts (open/commented/closed/reopened)
   - ✅ Notes closed with comments (engagement metric)

5. **Historical Analysis** ⭐⭐⭐⭐⭐
   - ✅ Year-over-year comparisons
   - ✅ First/last note tracking
   - ✅ Per-year breakdowns

### ⚠️ PARTIALLY Available in Datamarts

1. **Resolution Time Analysis** ⭐⭐⭐ (Can query from facts)
   - ⚠️ `days_to_resolution` exists in facts but not aggregated in datamarts
   - ⚠️ `days_to_resolution_active` (handles reopens) not in datamarts
   - ⚠️ `days_to_resolution_from_reopen` not in datamarts
   - **Recommendation**: Add average resolution time to datamarts

2. **Application Usage** ⭐⭐ (Available in facts, not aggregated)
   - ⚠️ Application tracking exists in facts
   - ⚠️ Version tracking exists
   - **Recommendation**: Add application statistics to datamarts

3. **Comment Quality Metrics** ⭐⭐⭐ (Available in facts)
   - ⚠️ `comment_length` exists in facts
   - ⚠️ `has_url` exists in facts
   - ⚠️ `has_mention` exists in facts
   - **Recommendation**: Add quality metrics to datamarts (avg length, % with URLs, % with mentions)

4. **Reopen Patterns** ⭐⭐⭐
   - ✅ Total reopen count available
   - ⚠️ Reopen rate (reopens/total opens) not precomputed
   - ⚠️ Notes with multiple reopens not tracked
   - **Recommendation**: Add reopen analysis metrics

5. **Local Time Analysis** ⭐⭐ (Available in facts)
   - ⚠️ Timezone support exists
   - ⚠️ Local time hour-of-week exists
   - ⚠️ Season analysis exists
   - **Recommendation**: Add local time patterns to datamarts

### ❌ MISSING from Datamarts (Available in Star Schema)

1. **Resolution Time Metrics** ⭐⭐⭐⭐⭐
   - ❌ Average resolution time by country
   - ❌ Median resolution time by country
   - ❌ Resolution time by year/month
   - ❌ Notes resolution rate (resolved/total opened)
   - ❌ Notes still open (tracking active issues)

2. **Application Statistics** ⭐⭐⭐⭐
   - ❌ Application breakdown by country
   - ❌ Application usage trends over time
   - ❌ Version adoption rates
   - ❌ Mobile vs desktop usage

3. **Content Quality Metrics** ⭐⭐⭐⭐
   - ❌ Average comment length by country/user
   - ❌ Percentage of comments with URLs
   - ❌ Percentage of comments with mentions
   - ❌ Engagement rate (comments/note)

4. **User Behavior Patterns** ⭐⭐⭐⭐
   - ❌ Notes opened but never closed by user
   - ❌ User response time (time to first comment)
   - ❌ Active vs inactive users (time since last action)
   - ❌ User collaboration patterns (mentions/replies)

5. **Geographic Distribution** ⭐⭐⭐⭐
   - ❌ Continent-level aggregates (missing in datamartCountries)
   - ❌ Region-level aggregates (missing in datamartCountries)
   - ❌ Notes per country density (notes per km²)

6. **Temporal Deep Dive** ⭐⭐⭐⭐
   - ❌ Local time patterns by country (using timezone data)
   - ❌ Seasonal patterns (using season dimension)
   - ❌ Weekend vs weekday activity
   - ❌ Peak activity times (local time)

7. **Hashtag Analysis** ⭐⭐⭐
   - ❌ Most popular hashtags globally/by country
   - ❌ Hashtag usage trends over time
   - ❌ Hashtag correlation with resolution time
   - ❌ Hashtags in opening vs closing notes

8. **Problem Patterns** ⭐⭐⭐⭐⭐
   - ❌ Notes that took longest to resolve
   - ❌ Notes with most reopenings (problem notes)
   - ❌ Notes with most comments (controversial/active)
   - ❌ Recent vs old notes activity

9. **Productivity Metrics** ⭐⭐⭐⭐
   - ❌ Notes closed per user (daily/monthly/yearly)
   - ❌ Users closing most notes recently
   - ❌ Notes opened vs closed ratio by country
   - ❌ Notes resolution rate (closed/total ever opened)

10. **Community Health** ⭐⭐⭐⭐⭐

- ❌ Overall notes health score
- ❌ Backlog size (unresolved notes)
- ❌ New vs resolved notes ratio
- ❌ Notes age distribution

---

## 📋 Recommendations for Dashboard Implementation

### Phase 1: Use Existing Datamart Data (Quick Wins)

#### Dashboards Ready NOW

1. **Country Activity Dashboard**
   - ✅ Use `datamartCountries` table
   - Historical counts (whole/year/month/day)
   - Activity heatmaps
   - Contributor rankings
   - Peak activity dates

2. **User Profile Dashboard**
   - ✅ Use `datamartUsers` table
   - Historical activity
   - Geographic distribution
   - Working hours patterns
   - Badges and contributor type

3. **Global Overview Dashboard**
   - ✅ Aggregate from both datamarts
   - Total notes globally
   - Active countries/users
   - Activity trends over time

### Phase 2: Query Star Schema for Enhanced Metrics

#### Dashboards Requiring Star Schema Queries

1. **Resolution Time Dashboard** (Query `dwh.facts`)
   - Average resolution time by country
   - Median resolution time
   - Resolution time trends
   - Notes with longest resolution time
   - Top problem notes (multiple reopens)

2. **Application Usage Dashboard** (Query `dwh.facts`)
   - Application breakdown by country
   - Usage trends over time
   - Version adoption
   - Mobile vs desktop

3. **Content Quality Dashboard** (Query `dwh.facts`)
   - Average comment length
   - URL usage rate
   - Mention rate
   - Engagement metrics

### Phase 3: Add Missing Metrics to Datamarts

#### Recommended Enhancements

1. **Resolution Time Metrics** (Add to datamarts)

   ```sql
   -- Average resolution time
   avg_days_to_resolution DECIMAL,
   median_days_to_resolution DECIMAL,
   notes_resolved_count INTEGER,
   notes_still_open_count INTEGER,
   resolution_rate DECIMAL -- (resolved/total opened)
   ```

2. **Application Statistics** (Add to datamarts)

   ```sql
   applications_used JSON, -- {app_id: count}
   applications_used_recent JSON,
   most_used_application VARCHAR,
   mobile_apps_count INTEGER,
   desktop_apps_count INTEGER
   ```

3. **Content Quality Metrics** (Add to datamarts)

   ```sql
   avg_comment_length DECIMAL,
   comments_with_url_pct DECIMAL,
   comments_with_mention_pct DECIMAL,
   avg_comments_per_note DECIMAL
   ```

4. **Community Health Metrics** (Add to datamarts)
   ```sql
   active_notes_count INTEGER,
   resolved_notes_count INTEGER,
   notes_backlog_size INTEGER,
   resolution_rate DECIMAL,
   notes_age_distribution JSON -- {age_range: count}
   ```

---

## 🔧 Implementation Recommendations

### 1. **Query Performance**

- ✅ Datamarts are already optimized for common queries
- ⚠️ Complex star schema queries may be slow (consider materialized views)
- 💡 Consider adding indexes on frequently queried fields

### 2. **Data Freshness**

- ✅ Datamarts update incrementally (only modified countries/users)
- ✅ Activity tiles update daily
- ⚠️ Real-time dashboards will require direct queries to `dwh.facts`

### 3. **JSON Export**

- ✅ `exportDatamartsToJSON.sh` already exports datamart data
- ⚠️ Consider expanding JSON schema to include new metrics
- 💡 Add API endpoints for real-time queries

### 4. **Dashboard Architecture**

**Recommended Structure:**

```
Level 1: Global Overview (datamartCountries aggregated)
  - Total notes globally
  - Active countries/users
  - Trends over time

Level 2: Country Drill-Down (datamartCountries)
  - Country-specific metrics
  - Historical trends
  - Contributors

Level 3: User Profiles (datamartUsers)
  - User-specific metrics
  - Geographic distribution
  - Badges

Level 4: Deep Analytics (dwh.facts queries)
  - Resolution time analysis
  - Application usage
  - Content quality
  - Problem notes
```

---

## ✅ Completeness Checklist

### Current State: ~60% Complete for Dashboard

- ✅ Temporal analysis: **COMPLETE**
- ✅ Geographic analysis: **COMPLETE** (countries only)
- ✅ User engagement: **COMPLETE**
- ⚠️ Resolution metrics: **PARTIAL** (data available, not aggregated)
- ⚠️ Application stats: **MISSING from datamarts**
- ⚠️ Content quality: **MISSING from datamarts**
- ⚠️ Productivity metrics: **MISSING from datamarts**
- ⚠️ Community health: **MISSING from datamarts**

### Path to 100% Complete

**Priority 1 (Quick Wins):**

1. Add resolution time aggregates to datamarts
2. Add notes backlog tracking
3. Add resolution rate calculations

**Priority 2 (High Value):** 4. Add application statistics to datamarts 5. Add content quality
metrics to datamarts 6. Add user behavior patterns to datamarts

**Priority 3 (Enhancement):** 7. Add continent/region aggregates 8. Add local time pattern
analysis 9. Add seasonal patterns analysis 10. Add hashtag deep dive analysis

---

## 🎯 Conclusion

The OSM Notes Analytics data warehouse has **excellent coverage** for temporal and geographic
analysis. The datamarts provide **ready-to-use data** for country and user dashboards. However, to
create a **comprehensive dashboard**, additional metrics should be added to the datamarts or queried
directly from the star schema.

**Recommended Next Steps:**

1. Start with existing datamart data for quick wins
2. Query star schema for resolution time and application metrics
3. Gradually enhance datamarts with missing metrics
4. Consider materialized views for complex queries
5. Expand JSON export schema for new metrics

---

## ✅ Implementation Status (October 2025)

### Completed Enhancements

The following enhancements have been implemented in October 2025:

#### ✅ Phase 1: Resolution Metrics (Implemented)

- `avg_days_to_resolution` - Average days to resolve notes
- `median_days_to_resolution` - Median days to resolve notes
- `notes_resolved_count` - Count of resolved notes
- `notes_still_open_count` - Count of open notes
- `resolution_rate` - Percentage of resolved notes

#### ✅ Phase 2: Application Statistics (Implemented)

- `applications_used` - JSON array of applications used
- `most_used_application_id` - ID of most used application
- `mobile_apps_count` - Count of mobile apps used
- `desktop_apps_count` - Count of desktop/web apps used

#### ✅ Phase 3: Content Quality Metrics (Implemented)

- `avg_comment_length` - Average comment length in characters
- `comments_with_url_count` - Comments containing URLs
- `comments_with_url_pct` - Percentage of comments with URLs
- `comments_with_mention_count` - Comments containing mentions
- `comments_with_mention_pct` - Percentage of comments with mentions
- `avg_comments_per_note` - Average comments per note

#### ✅ Phase 4: Community Health Metrics (Implemented)

- `active_notes_count` - Currently open notes
- `notes_backlog_size` - Notes opened but not resolved
- `notes_age_distribution` - JSON distribution of note ages
- `notes_created_last_30_days` - Recent creation activity
- `notes_resolved_last_30_days` - Recent resolution activity

#### ✅ Phase 5: High Priority Metrics (Implemented - January 2025)

**Application Trends:**

- `application_usage_trends` - JSON array of application usage trends by year (countries & users)
- `version_adoption_rates` - JSON array of version adoption rates by year (countries & users)

**Community Health (Countries):**

- `notes_health_score` - Overall notes health score (0-100) based on resolution rate, backlog, and
  activity
- `new_vs_resolved_ratio` - Ratio of new notes created vs resolved notes (last 30 days)

**User Behavior (Users):**

- `user_response_time` - Average time in days from note open to first comment by user
- `days_since_last_action` - Days since user last performed any action
- `collaboration_patterns` - JSON object with collaboration metrics (mentions, replies,
  collaboration score)

### Testing Coverage

- ✅ 197 total tests (22 new tests for high priority metrics)
- ✅ 90%+ ETL function coverage
- ✅ All datamart calculations validated
- ✅ Tests for all new metrics included

---

**Total Metrics Available:**

- Star Schema (dwh.facts): **~50 fields**
- datamartCountries: **~77 fields** (7 new high priority metrics)
- datamartUsers: **~78 fields** (8 metrics including notes_opened_but_not_closed_by_user)
- **Total unique metrics: ~158**
- **Dashboard-ready: ~98 metrics**
- **Needs aggregation: ~60 metrics**
