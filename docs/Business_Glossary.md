---
title: "Business Glossary"
description: "This glossary serves multiple purposes:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "documentation"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Business Glossary

This document provides business definitions for terms, concepts, and metrics used in the
OSM-Notes-Analytics system. These definitions are written from a business perspective to help
stakeholders understand what the data means and how to interpret it.

## Overview

This glossary serves multiple purposes:

- **Communication**: Common language between technical and business teams
- **Documentation**: Clear definitions for metrics and terms
- **Onboarding**: Help new team members understand the domain
- **Compliance**: Documented business rules and definitions

## Core Business Terms

### Note

**Definition**: A user-reported issue or feedback about the OpenStreetMap data. Notes represent
discrepancies between reality and what's mapped, requests for mapping, or questions about map
features.

**Business Context**: Notes are the primary mechanism for users to provide feedback to the OSM
community. They can be opened, commented on, closed (resolved), or reopened if the issue persists.

**Types of Note Actions**:

- **Opened**: A new note is created
- **Commented**: Someone adds a comment to an existing note
- **Closed**: The note is marked as resolved
- **Reopened**: A closed note is reopened because the issue wasn't fully resolved
- **Hidden**: The note is hidden (rare, usually for spam)

**Related Terms**: Note ID, Note Comment, Note Resolution

---

### Resolution

**Definition**: The process of addressing and closing a note, indicating that the reported issue has
been fixed or addressed.

**Business Context**: Resolution demonstrates that the OSM community is responsive to user feedback.
High resolution rates indicate a healthy, active mapping community.

**Resolution Metrics**:

- **Resolution Rate**: Percentage of opened notes that have been closed
- **Days to Resolution**: Time from note opening to closure
- **Resolution Quality**: Whether notes are closed with explanatory comments

**Related Terms**: Days to Resolution, Resolution Rate, Closed Note

---

### Active User

**Definition**: A user who has created or resolved at least one note within a specified time period.

**Business Context**: Active users are the core contributors to the OSM notes ecosystem. Tracking
active users helps measure community engagement and growth.

**Time Periods**:

- **Currently Active**: Action in the last 30 days
- **Yearly Active**: Action in the current year
- **Historically Active**: Has ever created or resolved a note

**Related Terms**: User Activity, Contributor, Mapper

---

### Community Health

**Definition**: Overall indicators of how well a geographic community (country, region) is managing
and resolving notes.

**Business Context**: Community health metrics help identify:

- Which communities need support
- Which communities are thriving
- Trends in note management effectiveness

**Indicators**:

- Resolution rate
- Average resolution time
- Backlog size (unresolved notes)
- Active user count
- Notes per active user ratio

**Related Terms**: Backlog, Resolution Rate, Active Notes

---

### Backlog

**Definition**: The number of notes that are currently open (not yet resolved).

**Business Context**: A large backlog may indicate:

- High volume of new issues
- Low resolution activity
- Complex issues requiring more time
- Need for community support

**Measurement**: Count of notes where `action_comment = 'opened'` and no subsequent
`action_comment = 'closed'` exists.

**Related Terms**: Open Notes, Unresolved Notes, Active Notes

---

### Contributor Type

**Definition**: Classification of users based on their contribution patterns and activity levels.

**Business Context**: Understanding contributor types helps:

- Identify power users who can mentor others
- Recognize bot/automated contributions
- Measure community diversity

**Types** (from `dwh.contributor_types`):

- **Normal**: Regular contributor
- **Power**: High-activity contributor
- **Epic**: Very high-activity contributor
- **Bot**: Automated contributions
- **Legendary**: Exceptional long-term contributor

**Related Terms**: User Classification, Experience Level, Automation Level

---

### Hashtag Campaign

**Definition**: Use of hashtags in notes to organize, track, or promote specific mapping initiatives
or themes.

**Business Context**: Hashtags enable:

- Campaign tracking (e.g., #MissingMaps, #Mapathon2024)
- Thematic organization
- Community coordination
- Performance measurement of initiatives

**Metrics**:

- Hashtag usage frequency
- Resolution rates for hashtagged notes
- Geographic distribution of hashtag usage

**Related Terms**: Hashtag, Campaign, Note Organization

---

## Metric Definitions

### Historical Counts

#### Total Notes Opened (`history_whole_open`)

**Business Name**: Total Notes Created  
**Definition**: Total number of notes this user (or country) opened/created across all time. This is a **count of notes**, not of days or activity sessions.  
**Formula**: `COUNT(*) WHERE action_dimension_id_user = user AND action_comment = 'opened'`  
**Unit**: Count (integer)  
**Interpretation**: Higher values indicate more active contribution to note creation. For users,
this shows their engagement level. For countries, this shows community activity.

**Time Periods**:

- `history_whole_open`: All time (2013-present)
- `history_year_open`: Current year
- `history_month_open`: Current month
- `history_day_open`: Today
- `history_2023_open`: Specific year (2013-2024+)

**Business Use Cases**:

- User profile: "This user has created 1,234 notes"
- Country comparison: "Colombia has 50,000 notes created"
- Trend analysis: "Notes created increased 20% this year"

---

#### Total Notes Closed (`history_whole_closed`)

**Business Name**: Total Notes Resolved  
**Definition**: Total number of notes this user (or country) closed/resolved across all time. This is a **count of notes**, not of days—a user can have closed many more notes than opened (e.g. 9,000 closed vs 226 opened) if they mainly resolve others’ notes.  
**Formula**: `COUNT(*) WHERE action_dimension_id_user = user AND action_comment = 'closed'`  
**Unit**: Count (integer)  
**Interpretation**: Higher values indicate more active contribution to note resolution. This is a
key indicator of community responsiveness.

**Business Use Cases**:

- User profile: "This user has resolved 567 notes"
- Country comparison: "Germany has resolved 80% of its notes"
- Impact measurement: "This user's resolution activity helps the community"

---

#### Notes Closed with Comment (`history_whole_closed_with_comment`)

**Business Name**: Resolved Notes with Explanations  
**Definition**: Number of notes closed that include an explanatory comment.  
**Formula**: `COUNT(*) WHERE action_comment = 'closed' AND comment_text IS NOT NULL`  
**Unit**: Count (integer)  
**Interpretation**: Higher values indicate better communication and explanation when resolving
notes. This is a quality indicator.

**Business Use Cases**:

- Quality measurement: "80% of resolutions include explanations"
- User behavior: "This user always explains their resolutions"
- Community standards: "Our community values explanatory closures"

---

#### Total Comments (`history_whole_commented`)

**Business Name**: Total Comments Added  
**Definition**: Total number of comments added to notes (excluding opening/closing comments).  
**Formula**: `COUNT(*) WHERE action_comment = 'commented'`  
**Unit**: Count (integer)  
**Interpretation**: Higher values indicate more engagement and discussion around notes. Shows
collaborative activity.

**Business Use Cases**:

- Engagement measurement: "This note has 15 comments (active discussion)"
- User activity: "This user actively participates in note discussions"
- Community collaboration: "High comment counts show active community"

---

#### Total Reopenings (`history_whole_reopened`)

**Business Name**: Total Notes Reopened  
**Definition**: Number of times notes were reopened after being closed.  
**Formula**: `COUNT(*) WHERE action_comment = 'reopened'`  
**Unit**: Count (integer)  
**Interpretation**: Higher values may indicate:

- Issues weren't fully resolved
- Complex problems requiring multiple attempts
- Quality control (reopening incorrectly closed notes)

**Business Use Cases**:

- Problem identification: "This note was reopened 3 times (complex issue)"
- Quality measurement: "Low reopen rate indicates good resolution quality"
- User behavior: "This user reopens notes that weren't properly fixed"

---

### Resolution Metrics

#### Average Days to Resolution (`resolution_avg_days`)

**Business Name**: Average Resolution Time  
**Definition**: Average number of days from when a note is opened until it is closed.  
**Formula**: `AVG(days_to_resolution) WHERE days_to_resolution IS NOT NULL`  
**Unit**: Days (decimal)  
**Interpretation**: Lower values indicate faster resolution. Typical values:

- **Excellent**: < 7 days
- **Good**: 7-30 days
- **Acceptable**: 30-90 days
- **Needs Improvement**: > 90 days

**Business Use Cases**:

- Performance measurement: "Average resolution time is 15 days"
- Community comparison: "Country A resolves notes 2x faster than Country B"
- Trend analysis: "Resolution time improved from 45 to 20 days this year"

**Note**: This metric only includes notes that have been closed. Open notes are excluded from the
average.

---

#### Median Days to Resolution (`resolution_median_days`)

**Business Name**: Median Resolution Time  
**Definition**: The middle value when all resolution times are sorted (50th percentile).  
**Formula**: `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution)`  
**Unit**: Days (integer)  
**Interpretation**: Less affected by outliers than average. If median is much lower than average,
there are some very long-resolution notes skewing the average.

**Business Use Cases**:

- Robust performance measurement: "Median resolution time is 8 days (vs 15 day average)"
- Outlier identification: "Average is high due to a few very old notes"
- Community health: "50% of notes resolve within 8 days"

---

#### Resolution Rate (`resolution_rate`)

**Business Name**: Note Resolution Rate  
**Definition**: Percentage of opened notes that have been closed (resolved).  
**Formula**: `(COUNT(*) WHERE action_comment = 'closed') / (COUNT(*) WHERE action_comment = 'opened') * 100`  
**Unit**:
Percentage (0-100)  
**Interpretation**: Higher values indicate better community responsiveness:

- **Excellent**: > 80%
- **Good**: 60-80%
- **Acceptable**: 40-60%
- **Needs Improvement**: < 40%

**Business Use Cases**:

- Community health: "Colombia has an 85% resolution rate"
- Trend analysis: "Resolution rate improved from 60% to 75% this year"
- Comparison: "Country A resolves 90% of notes, Country B resolves 50%"

**Note**: This is a ratio, not a count. A rate of 75% means 3 out of 4 notes are resolved.

---

#### Days to Resolution Active (`days_to_resolution_active`)

**Business Name**: Total Days Note Was Open  
**Definition**: Sum of all days a note was in open status, accounting for reopens.  
**Formula**: Sum of all open periods (from open/reopen to close/reopen)  
**Unit**: Days (integer)  
**Interpretation**: Accounts for notes that were reopened. If a note was open for 10 days, closed,
then reopened for 5 more days, this metric = 15 days.

**Business Use Cases**:

- Accurate time tracking: "This note was open for 45 total days (including reopens)"
- Complex issue measurement: "Notes with reopens take longer to fully resolve"
- Quality analysis: "High active days may indicate persistent problems"

**Difference from `days_to_resolution`**: This metric handles reopens correctly, while
`days_to_resolution` only measures first open to final close.

---

### Application Statistics

#### Mobile Applications Count (`applications_mobile_count`)

**Business Name**: Number of Mobile Apps Used  
**Definition**: Count of distinct mobile applications used to create notes.  
**Formula**: `COUNT(DISTINCT dimension_application_creation) WHERE platform = 'mobile'`  
**Unit**: Count (integer)  
**Interpretation**: Higher values indicate diverse mobile app usage. Shows mobile mapping adoption.

**Business Use Cases**:

- Platform adoption: "Users in this country use 5 different mobile apps"
- Technology trends: "Mobile app usage increased 30% this year"
- User behavior: "This user creates notes from 3 different mobile apps"

---

#### Desktop Applications Count (`applications_desktop_count`)

**Business Name**: Number of Desktop Apps Used  
**Definition**: Count of distinct desktop applications used to create notes.  
**Formula**: `COUNT(DISTINCT dimension_application_creation) WHERE platform = 'desktop'`  
**Unit**: Count (integer)  
**Interpretation**: Higher values indicate diverse desktop tool usage. Shows desktop mapping
adoption.

**Business Use Cases**:

- Platform comparison: "Desktop users use more diverse tools than mobile users"
- Tool adoption: "JOSM and iD are the most common desktop tools"
- User preferences: "This user prefers desktop tools for note creation"

---

#### Most Used Application (`application_most_used`)

**Business Name**: Primary Application  
**Definition**: The application most frequently used to create notes.  
**Formula**: `MODE() WITHIN GROUP (ORDER BY dimension_application_creation)`  
**Unit**: Application name (string)  
**Interpretation**: Shows the preferred tool for note creation. Common values: JOSM, iD,
MapComplete, StreetComplete.

**Business Use Cases**:

- Tool popularity: "iD is the most used application in this country"
- User preference: "This user primarily uses JOSM"
- Platform trends: "Mobile apps are becoming the primary tool"

---

### Content Quality Metrics

#### Average Comment Length (`content_avg_comment_length`)

**Business Name**: Average Comment Length  
**Definition**: Average number of characters in comments added to notes.  
**Formula**: `AVG(comment_length) WHERE comment_length IS NOT NULL`  
**Unit**: Characters (decimal)  
**Interpretation**: Higher values may indicate:

- More detailed explanations
- Better communication
- More thorough problem descriptions

**Business Use Cases**:

- Communication quality: "Average comment is 150 characters (detailed)"
- User behavior: "This user writes detailed comments (avg 200 chars)"
- Community standards: "Longer comments correlate with better resolution rates"

---

#### Comments with URLs (`content_urls_count`)

**Business Name**: Comments Containing Links  
**Definition**: Number of comments that contain URLs (web links).  
**Formula**: `COUNT(*) WHERE has_url = TRUE`  
**Unit**: Count (integer)  
**Interpretation**: URLs in comments often provide:

- Reference materials
- Evidence for the issue
- Related information
- External resources

**Business Use Cases**:

- Quality indicator: "30% of comments include reference links"
- User behavior: "This user frequently provides supporting links"
- Information sharing: "URLs help provide context for note issues"

---

#### Comments with Mentions (`content_mentions_count`)

**Business Name**: Comments Mentioning Other Users  
**Definition**: Number of comments that mention other users (using @username format).  
**Formula**: `COUNT(*) WHERE has_mention = TRUE`  
**Unit**: Count (integer)  
**Interpretation**: Mentions indicate:

- Direct communication
- Collaboration
- Requesting help
- Acknowledging contributions

**Business Use Cases**:

- Collaboration measurement: "This note has 5 mentions (active collaboration)"
- User engagement: "This user frequently mentions others (collaborative)"
- Community interaction: "High mention count shows active discussion"

---

### Temporal Patterns

#### Working Hours of Week (`working_hours_of_week_opening`)

**Business Name**: Activity by Hour of Week  
**Definition**: JSON array showing note activity for each of the 168 hours of the week (7 days × 24
hours).  
**Formula**: `json_agg(action_count) GROUP BY action_dimension_id_hour_of_week ORDER BY hour_of_week`  
**Unit**:
JSON array (168 integers)  
**Interpretation**: Shows when users are most active:

- **Weekdays 9-17**: Typical work hours
- **Evenings**: After-work activity
- **Weekends**: Leisure time activity
- **Night hours**: Different timezone or dedicated mappers

**Business Use Cases**:

- Activity patterns: "Users are most active Tuesday-Thursday 14:00-16:00"
- Timezone analysis: "Activity peaks at different hours (global community)"
- User behavior: "This user maps primarily on weekends"

**Format**: `[count_hour_0, count_hour_1, ..., count_hour_167]` where hour 0 = Sunday 00:00

---

#### Last Year Activity (`last_year_activity`)

**Business Name**: GitHub-Style Activity Heatmap  
**Definition**: String representation of activity over the last year (371 characters, one per
day).  
**Formula**: Character encoding of daily activity counts  
**Unit**: String (371 characters)  
**Interpretation**: Visual representation similar to GitHub contribution graph:

- Each character represents one day
- Character intensity shows activity level
- Patterns show consistency and engagement

**Business Use Cases**:

- Visual activity display: "Show activity heatmap on user profile"
- Consistency measurement: "This user maps consistently (no gaps)"
- Trend visualization: "Activity increased in recent months"

**Format**: 371 characters (one per day for last year), encoded activity levels

---

### Geographic Patterns

#### Countries Where User Opens Notes (`countries_open_notes`)

**Business Name**: User's Geographic Contribution Areas  
**Definition**: JSON array of country IDs where a user has opened notes.  
**Formula**: `json_agg(DISTINCT dimension_id_country) WHERE action_comment = 'opened'`  
**Unit**: JSON array of integers  
**Interpretation**: Shows geographic diversity of user contributions:

- **Single country**: Local mapper
- **Multiple countries**: Traveling mapper or global contributor
- **Many countries**: Very active global contributor

**Business Use Cases**:

- User profile: "This user contributes in 5 countries"
- Geographic diversity: "This user maps globally, not just locally"
- Contribution scope: "User focuses on specific region"

---

#### Top Countries by Activity (`ranking_countries_opening_2013`)

**Business Name**: Country Rankings by Year  
**Definition**: JSON array of top countries ranked by note activity for a specific year.  
**Formula**: `json_agg(country_id ORDER BY activity_count DESC LIMIT 10)`  
**Unit**: JSON array of objects (country_id, count, rank)  
**Interpretation**: Shows which countries are most active in note creation for that year.

**Business Use Cases**:

- Leaderboards: "Top 10 countries by note activity in 2023"
- Trend analysis: "Country rankings changed over time"
- Community comparison: "Compare activity across countries"

---

### User Classification Metrics

#### Contributor Type (`id_contributor_type`)

**Business Name**: User Contribution Classification  
**Definition**: Classification of user based on activity level and patterns.  
**Formula**: Classification algorithm based on:

- Total actions
- Activity consistency
- Time since first action
- Automation patterns

**Unit**: Integer (FK to `dwh.contributor_types`)  
**Types**:

- **Normal**: Regular contributor (most users)
- **Power**: High-activity contributor
- **Epic**: Very high-activity contributor
- **Bot**: Automated contributions
- **Legendary**: Exceptional long-term contributor

**Business Use Cases**:

- User recognition: "This user is classified as Power Contributor"
- Community analysis: "10% of users are Power Contributors"
- Mentorship: "Power Contributors can mentor Normal Contributors"

---

## Business Rules

### Rule 1: One Fact Per Action

- **Business Rule**: Each note action (open, comment, close, reopen) creates exactly one fact row
- **Rationale**: Ensures accurate counting and prevents double-counting
- **Exception**: None

### Rule 2: Resolution Metrics Only for Closed Notes

- **Business Rule**: Resolution time metrics are only calculated for notes that have been closed
- **Rationale**: Open notes don't have a resolution time yet
- **Impact**: Resolution averages exclude currently open notes

### Rule 3: Recent Open Date Always Set

- **Business Rule**: `recent_opened_dimension_id_date` must always have a value (NOT NULL)
- **Rationale**: Needed for accurate resolution calculations, especially for reopened notes
- **Enforcement**: Set during unify step after all facts are loaded

### Rule 4: Datamart Incremental Updates

- **Business Rule**: Only update datamarts for entities that have changed (`modified = TRUE`)
- **Rationale**: Improves performance by avoiding unnecessary recalculations
- **Impact**: Datamarts may be slightly stale for unchanged entities

### Rule 5: JSON Schema Validation

- **Business Rule**: All exported JSON must validate against schema before being written
- **Rationale**: Ensures data quality and prevents invalid exports
- **Action on Failure**: Keep existing files, log error, exit with error code

---

## Metric Calculation Examples

### Example 1: User Resolution Rate

**Scenario**: User "AngocA" has opened 100 notes and closed 75 notes.

**Calculation**:

```
resolution_rate = (75 / 100) * 100 = 75%
```

**Business Interpretation**: "AngocA has resolved 75% of the notes they created, which is above the
community average of 65%. This indicates strong follow-through on reported issues."

---

### Example 2: Country Average Resolution Time

**Scenario**: Colombia has 1,000 closed notes with resolution times: 500 notes at 5 days, 300 at 10
days, 200 at 30 days.

**Calculation**:

```
Average = (500*5 + 300*10 + 200*30) / 1000
        = (2500 + 3000 + 6000) / 1000
        = 11.5 days
```

**Business Interpretation**: "Colombia's average resolution time is 11.5 days, which is excellent
(below 30 days). Most notes resolve quickly, with some complex issues taking longer."

---

### Example 3: Working Hours Pattern

**Scenario**: User's `working_hours_of_week_opening` shows peak at hour 80 (Thursday 8:00 AM).

**Calculation**:

```
Hour 80 = (Thursday = day 4) * 24 + 8 = 80 + 8 = 88
Wait, let's recalculate:
Sunday = 0-23 (hours 0-23)
Monday = 24-47 (hours 24-47)
Tuesday = 48-71 (hours 48-71)
Wednesday = 72-95 (hours 72-95)
Thursday = 96-119 (hours 96-119)

Hour 80 = Wednesday 8:00 AM
```

**Business Interpretation**: "This user is most active on Wednesday mornings, suggesting they map
during work hours or have a regular mapping schedule."

---

## Related Documentation

- **[Metric Definitions](Metric_Definitions.md)**: Complete reference for all 77+ (countries) and
  78+ (users) metrics with detailed definitions
- **[Data Dictionary](DWH_Star_Schema_Data_Dictionary.md)**: Technical column definitions
- **[Data Lineage](Data_Lineage.md)**: How metrics are calculated
- **[Dashboard Analysis](Dashboard_Analysis.md)**: Available metrics for dashboards

---

## References

- [DAMA DMBOK - Business Glossary](https://www.dama.org/)
- [Kimball Group - Business Metrics](https://www.kimballgroup.com/)
- [OpenStreetMap Notes Documentation](https://wiki.openstreetmap.org/wiki/Notes)
