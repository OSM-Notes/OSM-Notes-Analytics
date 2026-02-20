---
title: "Architecture Diagram"
description: "The architecture documentation uses the C4 model:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "architecture"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Architecture Diagram

This document provides architecture diagrams for the OSM-Notes-Analytics system, following the C4
model for software architecture documentation. These diagrams help understand the system structure,
components, and their interactions.

## Overview

The architecture documentation uses the C4 model:

- **Level 1 (System Context)**: System and its relationships with external entities
- **Level 2 (Container)**: High-level technical building blocks
- **Level 3 (Component)**: Components within containers (detailed in other docs)

## C4 Level 1: System Context Diagram

Shows the OSM-Notes-Analytics system and its relationships with users and external systems.

```mermaid
graph TB
    subgraph External["External Systems"]
        OSM_API[OSM Notes API<br/>openstreetmap.org]
        PLANET[OSM Planet Dumps<br/>planet.openstreetmap.org]
        OVERPASS[Overpass API<br/>overpass-api.de]
    end

    subgraph Ecosystem["OSM Notes Ecosystem (8 Projects)"]
        INGESTION[OSM-Notes-Ingestion<br/>Data Ingestion System<br/>Base Project]
        ANALYTICS[OSM-Notes-Analytics<br/>data warehouse & ETL<br/>This System]
        API[OSM-Notes-API<br/>REST API]
        DATA[OSM-Notes-Data<br/>JSON Files<br/>GitHub Pages]
        VIEWER[OSM-Notes-Viewer<br/>Web Application]
        WMS[OSM-Notes-WMS<br/>Web Map Service]
        MONITORING[OSM-Notes-Monitoring<br/>Monitoring & Alerting]
        COMMON[OSM-Notes-Common<br/>Shared Libraries<br/>Git Submodule]
    end

    subgraph Users["Users"]
        DATA_ENG[Data Engineers<br/>ETL Operations]
        ANALYSTS[Data Analysts<br/>Query DWH]
        WEB_USERS[Web Users<br/>View Dashboards]
        DEVS[Developers<br/>Maintain System]
    end

    OSM_API -->|Raw Note Data| INGESTION
    PLANET -->|Historical Data| INGESTION
    OVERPASS -->|Boundary Data| INGESTION

    INGESTION -->|Base Tables| ANALYTICS
    INGESTION -->|Same Database| WMS
    ANALYTICS -->|JSON Datamarts| DATA
    ANALYTICS -->|Data Warehouse| API
    DATA -->|JSON Files| VIEWER
    VIEWER -->|Visualizations| WEB_USERS

    COMMON -.->|Shared Libraries| INGESTION
    COMMON -.->|Shared Libraries| ANALYTICS
    COMMON -.->|Shared Libraries| WMS
    COMMON -.->|Shared Libraries| MONITORING

    MONITORING -.->|Monitors| INGESTION
    MONITORING -.->|Monitors| ANALYTICS
    MONITORING -.->|Monitors| API
    MONITORING -.->|Monitors| WMS
    MONITORING -.->|Monitors| DATA
    MONITORING -.->|Monitors| VIEWER

    DATA_ENG -->|Run ETL| ANALYTICS
    ANALYSTS -->|Query DWH| ANALYTICS
    DEVS -->|Maintain| ANALYTICS
```

**System Relationships:**

- **OSM-Notes-Ingestion**: Upstream system providing base data (base project)
- **OSM-Notes-Analytics**: This system (ETL and data warehouse)
- **OSM-Notes-API**: Reads from Analytics data warehouse (optional consumer)
- **OSM-Notes-Data**: JSON files exported from Analytics (served via GitHub Pages)
- **OSM-Notes-Viewer**: Downstream system consuming JSON exports from Data
- **OSM-Notes-WMS**: Uses same database as Ingestion (geographic visualization)
- **OSM-Notes-Monitoring**: Monitors all ecosystem components
- **OSM-Notes-Common**: Shared library used by multiple systems (Ingestion, Analytics, WMS,
  Monitoring)

**User Types:**

- **Data Engineers**: Run ETL processes, maintain data pipeline
- **Data Analysts**: Query data warehouse for analysis
- **Web Users**: Consume visualizations via web interface
- **Developers**: Maintain and enhance the system

---

## C4 Level 2: Container Diagram

Shows the high-level technical building blocks (containers) within the OSM-Notes-Analytics system.

```mermaid
graph TB
    subgraph Analytics_System["OSM-Notes-Analytics System"]
        subgraph Scripts["Bash Scripts Layer"]
            ETL_SCRIPT[ETL.sh<br/>Main ETL Orchestration]
            DATAMART_USERS[datamartUsers.sh<br/>User Analytics]
            DATAMART_COUNTRIES[datamartCountries.sh<br/>Country Analytics]
            EXPORT_JSON[exportDatamartsToJSON.sh<br/>JSON Export]
            PROFILE[profile.sh<br/>Profile Generator]
        end

        subgraph SQL_Layer["SQL Layer"]
            ETL_SQL[ETL SQL Scripts<br/>Schema Creation]
            STAGING_SQL[Staging Procedures<br/>Data Transformation]
            DATAMART_SQL[Datamart SQL<br/>Aggregations]
        end

        subgraph Database["PostgreSQL Database"]
            BASE_SCHEMA[public Schema<br/>Base Tables<br/>from Ingestion]
            DWH_SCHEMA[dwh Schema<br/>Star Schema DWH]
            STAGING_SCHEMA[staging Schema<br/>Temporary Processing]
        end

        subgraph Libraries["Shared Libraries"]
            COMMON_LIBS[OSM-Notes-Common<br/>lib/osm-common/]
        end

        subgraph Config["Configuration"]
            PROPS[properties.sh<br/>Database Config]
            ETL_PROPS[etl.properties<br/>ETL Config]
        end

        subgraph Output["Output Files"]
            JSON_FILES[JSON Files<br/>output/json/]
        end
    end

    subgraph External_Systems["External Systems"]
        INGESTION_SYS[OSM-Notes-Ingestion<br/>Base Tables Provider]
        VIEWER_SYS[OSM-Notes-Viewer<br/>JSON Consumer]
    end

    INGESTION_SYS -->|Base Tables| BASE_SCHEMA

    ETL_SCRIPT -->|Executes| ETL_SQL
    ETL_SCRIPT -->|Reads| PROPS
    ETL_SCRIPT -->|Reads| ETL_PROPS
    ETL_SCRIPT -->|Uses| COMMON_LIBS

    ETL_SQL -->|Creates| DWH_SCHEMA
    STAGING_SQL -->|Uses| STAGING_SCHEMA
    STAGING_SQL -->|Reads| BASE_SCHEMA
    STAGING_SQL -->|Writes| DWH_SCHEMA

    DATAMART_USERS -->|Executes| DATAMART_SQL
    DATAMART_COUNTRIES -->|Executes| DATAMART_SQL
    DATAMART_SQL -->|Reads| DWH_SCHEMA
    DATAMART_SQL -->|Writes| DWH_SCHEMA

    EXPORT_JSON -->|Reads| DWH_SCHEMA
    EXPORT_JSON -->|Writes| JSON_FILES
    EXPORT_JSON -->|Uses| COMMON_LIBS

    JSON_FILES -->|Consumed by| VIEWER_SYS

    PROFILE -->|Reads| DWH_SCHEMA
```

**Containers:**

1. **Bash Scripts Layer**
   - Entry points for system operations
   - Orchestrates ETL and datamart processes
   - Handles error recovery and logging

2. **SQL Layer**
   - Database schema definitions
   - Staging procedures for transformations
   - Datamart aggregation logic

3. **PostgreSQL Database**
   - **public schema**: Base tables from ingestion
   - **dwh schema**: Star schema data warehouse
   - **staging schema**: Temporary processing area

4. **Shared Libraries**
   - Common functions (logging, validation, error handling)
   - Shared via Git submodule

5. **Configuration**
   - Database connection settings
   - ETL performance and behavior settings

6. **Output Files**
   - JSON exports for web viewer
   - Validated and schema-checked

---

## Detailed Architecture Diagram

Shows components, data flows, and technologies in detail.

```mermaid
graph TB
    subgraph Data_Sources["Data Sources"]
        BASE_TABLES[Base Tables<br/>public schema<br/>PostgreSQL]
    end

    subgraph ETL_Process["ETL Process"]
        ETL_ORCHESTRATOR[ETL.sh<br/>Bash Script]
        STAGING_PROC[Staging Procedures<br/>PostgreSQL Functions]
        DIMENSION_LOADER[Dimension Loader<br/>SQL Scripts]
        FACT_LOADER[Fact Loader<br/>Parallel by Year]
        UNIFY[Unify Process<br/>Cross-Year Metrics]
    end

    subgraph Data_Warehouse["data warehouse"]
        FACTS_TABLE[facts Table<br/>Partitioned by Year<br/>~20M+ rows]
        DIM_TABLES[Dimension Tables<br/>users, countries,<br/>days, times, apps]
        INDEXES[Indexes & Constraints<br/>Performance Optimization]
    end

    subgraph Datamart_Process["Datamart Process"]
        USER_DATAMART[datamartUsers.sh<br/>Bash Script]
        COUNTRY_DATAMART[datamartCountries.sh<br/>Bash Script]
        GLOBAL_DATAMART[datamartGlobal.sh<br/>Bash Script]
        AGGREGATION_SQL[Aggregation SQL<br/>77+ (countries)<br/>78+ (users)]
    end

    subgraph Datamart_Storage["Datamart Storage"]
        DM_USERS[datamartusers<br/>~500K rows]
        DM_COUNTRIES[datamartcountries<br/>~200 rows]
        DM_GLOBAL[datamartglobal<br/>1 row]
    end

    subgraph Export_Process["Export Process"]
        EXPORT_SCRIPT[exportDatamartsToJSON.sh<br/>Bash Script]
        JSON_CONVERTER[SQL to JSON<br/>Conversion]
        VALIDATOR[Schema Validator<br/>JSON Schema]
        ATOMIC_WRITER[Atomic File Writer<br/>Temp → Final]
    end

    subgraph Output["Output"]
        JSON_USERS[JSON Users<br/>output/json/users/]
        JSON_COUNTRIES[JSON Countries<br/>output/json/countries/]
        JSON_INDEXES[JSON Indexes<br/>output/json/indexes/]
    end

    BASE_TABLES -->|Read| ETL_ORCHESTRATOR
    ETL_ORCHESTRATOR -->|Execute| STAGING_PROC
    STAGING_PROC -->|Transform| DIMENSION_LOADER
    STAGING_PROC -->|Transform| FACT_LOADER
    DIMENSION_LOADER -->|Write| DIM_TABLES
    FACT_LOADER -->|Write| FACTS_TABLE
    FACTS_TABLE -->|Unify| UNIFY
    UNIFY -->|Update| FACTS_TABLE
    FACTS_TABLE -->|Add| INDEXES

    FACTS_TABLE -->|Read| USER_DATAMART
    DIM_TABLES -->|Read| USER_DATAMART
    USER_DATAMART -->|Execute| AGGREGATION_SQL
    AGGREGATION_SQL -->|Write| DM_USERS

    FACTS_TABLE -->|Read| COUNTRY_DATAMART
    DIM_TABLES -->|Read| COUNTRY_DATAMART
    COUNTRY_DATAMART -->|Execute| AGGREGATION_SQL
    AGGREGATION_SQL -->|Write| DM_COUNTRIES

    FACTS_TABLE -->|Read| GLOBAL_DATAMART
    GLOBAL_DATAMART -->|Execute| AGGREGATION_SQL
    AGGREGATION_SQL -->|Write| DM_GLOBAL

    DM_USERS -->|Read| EXPORT_SCRIPT
    DM_COUNTRIES -->|Read| EXPORT_SCRIPT
    EXPORT_SCRIPT -->|Convert| JSON_CONVERTER
    JSON_CONVERTER -->|Validate| VALIDATOR
    VALIDATOR -->|Write| ATOMIC_WRITER
    ATOMIC_WRITER -->|Output| JSON_USERS
    ATOMIC_WRITER -->|Output| JSON_COUNTRIES
    ATOMIC_WRITER -->|Output| JSON_INDEXES
```

---

## Technology Stack

### Core Technologies

| Layer         | Technology     | Version | Purpose                          |
| ------------- | -------------- | ------- | -------------------------------- |
| **Database**  | PostgreSQL     | 12+     | Data storage and processing      |
| **Spatial**   | PostGIS        | 3.0+    | Geographic data support          |
| **Scripting** | Bash           | 4.0+    | ETL orchestration and automation |
| **SQL**       | PostgreSQL SQL | 12+     | Data transformations and queries |

### Supporting Technologies

| Component               | Technology        | Purpose                          |
| ----------------------- | ----------------- | -------------------------------- |
| **Logging**             | bash_logger.sh    | Structured logging (log4j-style) |
| **Validation**          | JSON Schema       | Export validation                |
| **Testing**             | BATS              | Bash script testing              |
| **CI/CD**               | GitHub Actions    | Automated testing and validation |
| **Code Quality**        | shellcheck, shfmt | Code linting and formatting      |
| **Parallel Processing** | GNU Parallel      | Year-based parallel ETL          |

### Shared Libraries

| Library                       | Location        | Purpose           |
| ----------------------------- | --------------- | ----------------- |
| **bash_logger.sh**            | lib/osm-common/ | Logging framework |
| **commonFunctions.sh**        | lib/osm-common/ | Common utilities  |
| **validationFunctions.sh**    | lib/osm-common/ | Data validation   |
| **errorHandlingFunctions.sh** | lib/osm-common/ | Error handling    |

---

## Component Interactions

### ETL Process Flow

```mermaid
sequenceDiagram
    participant ETL as ETL.sh
    participant SQL as SQL Scripts
    participant DB as PostgreSQL
    participant Staging as Staging Schema
    participant DWH as DWH Schema

    ETL->>DB: Check base tables exist
    ETL->>SQL: Execute ETL_20_createDWHTables.sql
    SQL->>DWH: Create star schema
    ETL->>SQL: Execute ETL_25_populateDimensionTables.sql
    SQL->>DWH: Populate dimensions
    ETL->>SQL: Execute Staging_31_createBaseStagingObjects.sql
    SQL->>Staging: Create staging tables
    ETL->>SQL: Execute Staging_35_initialFactsLoadExecute.sql (parallel by year)
    SQL->>Staging: Load facts per year
    SQL->>DWH: Copy from staging to facts
    ETL->>SQL: Execute Staging_50_unify.sql
    SQL->>DWH: Unify and calculate cross-year metrics
    ETL->>SQL: Execute ETL_40_addConstraintsIndexesTriggers.sql
    SQL->>DWH: Add indexes and constraints
```

### Datamart Process Flow

```mermaid
sequenceDiagram
    participant Script as datamartUsers.sh
    participant SQL as Datamart SQL
    participant DWH as DWH Schema
    participant DM as Datamart Table

    Script->>DWH: Check facts table exists
    Script->>SQL: Execute datamartUsers_11_createDatamartUsersTable.sql
    SQL->>DM: Create datamartusers table
    Script->>SQL: Execute datamartUsers_32_populateDatamartUsersTable.sql
    SQL->>DWH: Read facts + dimensions
    SQL->>SQL: Aggregate by user (78+ metrics)
    SQL->>DM: Write aggregated data
    Script->>DM: Verify row counts
```

### Export Process Flow

```mermaid
sequenceDiagram
    participant Export as exportDatamartsToJSON.sh
    participant DB as PostgreSQL
    participant Validator as Schema Validator
    participant FS as File System

    Export->>DB: Query datamartusers
    DB-->>Export: Return user rows
    Export->>Export: Convert SQL to JSON
    Export->>Validator: Validate JSON against schema
    Validator-->>Export: Validation result
    alt Valid
        Export->>FS: Write to temp directory
        Export->>FS: Move atomically to output/json/users/
    else Invalid
        Export->>Export: Log error, keep existing files
        Export->>Export: Exit with error code
    end
```

---

## Data Architecture

### Schema Organization

```mermaid
graph TD
    DB[PostgreSQL Database: notes_dwh]

    subgraph Public["Schema: public<br/>managed by OSM-Notes-Ingestion"]
        NOTES[notes]
        COMMENTS[note_comments]
        COMMENTS_TEXT[note_comments_text]
        USERS[users]
        COUNTRIES[countries]
    end

    subgraph DWH["Schema: dwh<br/>managed by OSM-Notes-Analytics"]
        subgraph Facts["facts partitioned by year"]
            F2013[facts_2013]
            F2014[facts_2014]
            FDOTS[...]
            F2025[facts_2025]
        end

        DIM_USERS[dimension_users]
        DIM_COUNTRIES[dimension_countries]
        DIM_DAYS[dimension_days]
        DIM_TIME_WEEK[dimension_time_of_week]
        DIM_APPS[dimension_applications]
        DIM_APP_VERS[dimension_application_versions]
        DIM_HASHTAGS[dimension_hashtags]
        DIM_TZ[dimension_timezones]
        DIM_SEASONS[dimension_seasons]
        DIM_AUTO[dimension_automation_level]
        DIM_EXP[dimension_experience_levels]

        DM_USERS[datamartusers]
        DM_COUNTRIES[datamartcountries]
        DM_GLOBAL[datamartglobal]
    end

    subgraph Staging["Schema: staging<br/>temporary, managed by ETL"]
        STAGE_2013[facts_2013 per-year staging]
        STAGE_2014[facts_2014 per-year staging]
        STAGE_DOTS[...]
    end

    DB --> Public
    DB --> DWH
    DB --> Staging

    Public --> NOTES
    Public --> COMMENTS
    Public --> COMMENTS_TEXT
    Public --> USERS
    Public --> COUNTRIES

    DWH --> Facts
    Facts --> F2013
    Facts --> F2014
    Facts --> FDOTS
    Facts --> F2025

    DWH --> DIM_USERS
    DWH --> DIM_COUNTRIES
    DWH --> DIM_DAYS
    DWH --> DIM_TIME_WEEK
    DWH --> DIM_APPS
    DWH --> DIM_APP_VERS
    DWH --> DIM_HASHTAGS
    DWH --> DIM_TZ
    DWH --> DIM_SEASONS
    DWH --> DIM_AUTO
    DWH --> DIM_EXP
    DWH --> DM_USERS
    DWH --> DM_COUNTRIES
    DWH --> DM_GLOBAL

    Staging --> STAGE_2013
    Staging --> STAGE_2014
    Staging --> STAGE_DOTS

    style DB fill:#90EE90
    style Public fill:#E0F6FF
    style DWH fill:#FFFFE0
    style Staging fill:#FFE4B5
```

### Partitioning Strategy

- **Facts Table**: Partitioned by year using `action_at` column
- **Benefits**: 10-50x faster date-based queries
- **Maintenance**: Can VACUUM/ANALYZE individual partitions
- **Parallel Processing**: Process multiple years simultaneously

See [Partitioning Strategy](Partitioning_Strategy.md) for details.

---

## Deployment Architecture

### Single Server Deployment

```mermaid
graph TB
    subgraph Server["Application Server"]
        subgraph Processes["Running Processes"]
            CRON[Cron Jobs<br/>Scheduled ETL]
            ETL_PROC[ETL Process<br/>Every 15 min/On-Demand]
            DATAMART_PROC[Datamart Process<br/>Daily]
            EXPORT_PROC[Export Process<br/>Every 15 min]
        end

        subgraph Storage["Local Storage"]
            SCRIPTS[Scripts<br/>bin/, sql/]
            CONFIG[Configuration<br/>etc/]
            OUTPUT[JSON Output<br/>output/json/]
            LOGS[Log Files<br/>/tmp/]
        end
    end

    subgraph Database_Server["Database Server"]
        POSTGRES[PostgreSQL<br/>+ PostGIS]
        DB_STORAGE[Database Files<br/>Base Tables + DWH]
    end

    subgraph External["External"]
        INGESTION[OSM-Notes-Ingestion<br/>Updates Base Tables]
        VIEWER[OSM-Notes-Viewer<br/>Reads JSON Files]
    end

    CRON -->|Triggers| ETL_PROC
    CRON -->|Triggers| DATAMART_PROC
    CRON -->|Triggers| EXPORT_PROC

    ETL_PROC -->|Reads| SCRIPTS
    ETL_PROC -->|Reads| CONFIG
    ETL_PROC -->|Writes| POSTGRES
    ETL_PROC -->|Writes| LOGS

    DATAMART_PROC -->|Reads| POSTGRES
    DATAMART_PROC -->|Writes| POSTGRES

    EXPORT_PROC -->|Reads| POSTGRES
    EXPORT_PROC -->|Writes| OUTPUT

    INGESTION -->|Updates| POSTGRES
    VIEWER -->|Reads| OUTPUT

    POSTGRES -->|Stores| DB_STORAGE
```

### Deployment Components

1. **Application Server**
   - Bash scripts and SQL files
   - Cron jobs for scheduling
   - Configuration files
   - Output directory for JSON files

2. **Database Server**
   - PostgreSQL with PostGIS
   - Base tables (public schema)
   - Data warehouse (dwh schema)
   - Staging area (staging schema)

3. **External Systems**
   - OSM-Notes-Ingestion: Updates base tables
   - OSM-Notes-Viewer: Consumes JSON exports

---

## Security Architecture

### Access Control

```mermaid
graph TB
    subgraph Users["User Roles"]
        DB_ADMIN[Database Admin<br/>Full Access]
        ETL_USER[ETL User<br/>Read public, Write dwh]
        READ_ONLY[Read-Only User<br/>Read dwh only]
        WEB_USER[Web User<br/>Read JSON files only]
    end

    subgraph Database["PostgreSQL"]
        PUBLIC_SCHEMA[public Schema<br/>Base Tables]
        DWH_SCHEMA[dwh Schema<br/>data warehouse]
        STAGING_SCHEMA[staging Schema<br/>Temporary]
    end

    subgraph Files["File System"]
        SCRIPTS_DIR[Scripts<br/>bin/, sql/]
        CONFIG_DIR[Config<br/>etc/]
        OUTPUT_DIR[JSON Output<br/>output/json/]
    end

    DB_ADMIN -->|Full Access| PUBLIC_SCHEMA
    DB_ADMIN -->|Full Access| DWH_SCHEMA
    DB_ADMIN -->|Full Access| STAGING_SCHEMA

    ETL_USER -->|Read| PUBLIC_SCHEMA
    ETL_USER -->|Read/Write| DWH_SCHEMA
    ETL_USER -->|Read/Write| STAGING_SCHEMA
    ETL_USER -->|Execute| SCRIPTS_DIR
    ETL_USER -->|Read| CONFIG_DIR

    READ_ONLY -->|Read Only| DWH_SCHEMA

    WEB_USER -->|Read Only| OUTPUT_DIR
```

**Security Practices:**

- Database credentials stored in `etc/properties.sh` (not in Git)
- JSON exports are read-only for web users
- ETL user has minimal required permissions
- Configuration files excluded from version control

---

## Performance Architecture

### Parallel Processing

```mermaid
graph TB
    ETL_MAIN[ETL.sh Main Process]

    subgraph Parallel_Years["Parallel Year Processing"]
        YEAR_2013[Year 2013<br/>Background Process]
        YEAR_2014[Year 2014<br/>Background Process]
        YEAR_2015[Year 2015<br/>Background Process]
        YEAR_N[Year N<br/>Background Process]
    end

    MERGE[Merge Results]
    FINALIZE[Finalize DWH]

    ETL_MAIN -->|Spawn| YEAR_2013
    ETL_MAIN -->|Spawn| YEAR_2014
    ETL_MAIN -->|Spawn| YEAR_2015
    ETL_MAIN -->|Spawn| YEAR_N

    YEAR_2013 -->|Complete| MERGE
    YEAR_2014 -->|Complete| MERGE
    YEAR_2015 -->|Complete| MERGE
    YEAR_N -->|Complete| MERGE

    MERGE -->|Wait All| FINALIZE
    FINALIZE -->|Complete| ETL_MAIN
```

**Performance Features:**

- **Parallel Processing**: Multiple years processed simultaneously
- **Partitioning**: Fast date-based queries
- **Indexing**: Optimized foreign keys and common queries
- **Incremental Updates**: Only process new data
- **Resource Monitoring**: Prevents system overload

---

## Scalability Considerations

### Current Architecture Supports

- **Data Volume**: ~20M+ fact rows, ~500K users, ~200 countries
- **Processing**: Parallel processing by year (12-13 parallel jobs)
- **Query Performance**: Partitioned tables, optimized indexes
- **Export**: Incremental JSON export (only changed entities)

### Future Scalability Options

1. **Horizontal Scaling**: Separate ETL and query servers
2. **Database Replication**: Read replicas for analytics queries
3. **Caching**: Redis cache for frequently accessed datamarts
4. **Distributed Processing**: Split ETL across multiple servers

---

## Related Documentation

- **[Data Flow Diagrams](Data_Flow_Diagrams.md)**: Data flow through the system
- **[Data Lineage](Data_Lineage.md)**: Data transformations and lineage
- **[DWH Star Schema ERD](DWH_Star_Schema_ERD.md)**: Database schema design
- **[ETL Enhanced Features](ETL_Enhanced_Features.md)**: ETL capabilities
- **[Troubleshooting Guide](Troubleshooting_Guide.md)**: Architecture-related issues

---

## References

- [C4 Model](https://c4model.com/) - Software architecture documentation
- [PostgreSQL Architecture](https://www.postgresql.org/docs/current/architecture.html)
- [Star Schema Design](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/star-schema/)
