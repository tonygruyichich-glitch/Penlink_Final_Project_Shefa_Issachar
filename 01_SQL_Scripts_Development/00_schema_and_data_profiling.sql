/* ==============================================================================
   File: 00_schema_and_data_profiling.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Author: Tony Gruyichich
   Description: Data quality audit and join key integrity check between
                OpenStreetMap supermarkets (`supermarkets_il`) and CBS registry
                (`Lamas_Israel_2026`).
   ============================================================================== */

-- Step 1: Aggregate supermarkets by city and check for duplicate primary keys (id)
WITH raw_supermarkets_grouped AS (
    SELECT
        city AS raw_city,
        TRIM(city) AS trimmed_city,
        COUNT(*) AS total_rows,
        COUNT(DISTINCT id) AS unique_supermarket_ids
    FROM `bqproj26.Final_Project_2026.supermarkets_il`
    GROUP BY
        city,
        TRIM(city)
),

-- Step 2: Extract official settlement identifiers and population from CBS (Lamas)
     lamas_cities AS (
         SELECT
             city_id,
             TRIM(city_name) AS clean_lamas_name,
             total_population
         FROM `bqproj26.Final_Project_2026.Lamas_Israel_2026`
     )

-- Step 3: Perform Join Key Integrity Audit to classify matching status
SELECT
    s.raw_city,
    s.trimmed_city,
    s.total_rows,
    s.unique_supermarket_ids,
    l.city_id AS matched_lamas_id,
    l.total_population,
    CASE
        WHEN s.trimmed_city IS NULL OR s.trimmed_city = '' THEN '1_MISSING_CITY_NULL'
        WHEN l.city_id IS NULL THEN '2_UNMATCHED_NAME'
        ELSE '3_EXACT_MATCH'
        END AS integrity_status
FROM raw_supermarkets_grouped AS s
         LEFT JOIN lamas_cities AS l
                   ON s.trimmed_city = l.clean_lamas_name
ORDER BY
    integrity_status ASC,
    s.unique_supermarket_ids DESC;