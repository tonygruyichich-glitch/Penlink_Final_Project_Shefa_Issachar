/* ==============================================================================
   File: 01_part1_eda_and_lamas_join.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Author: Tony Gruyichich
   Description: Part 1 - Descriptive statistics, central tendency, dispersion metrics,
                and retail saturation benchmarking for Yavne and major Israeli cities.
   ============================================================================== */

-- ==============================================================================
-- Query 1: Central Tendency & Dispersion (All Settlements vs. Active Retail Cities)
-- ==============================================================================
WITH supermarkets_by_city AS (
    SELECT
        TRIM(city) AS city_name_clean,
        COUNT(DISTINCT id) AS supermarket_count
    FROM `bqproj26.Final_Project_2026.supermarkets_il`
    WHERE city IS NOT NULL AND TRIM(city) != ''
GROUP BY TRIM(city)
    ),

    lamas_supermarkets_merged AS (
SELECT
    l.city_id,
    TRIM(l.city_name) AS city_name,
    l.napa,
    l.total_population,
    COALESCE(s.supermarket_count, 0) AS supermarket_count,
    ROUND(
    SAFE_DIVIDE(COALESCE(s.supermarket_count, 0) * 10000.0, l.total_population),
    2
    ) AS supermarkets_per_10k
FROM `bqproj26.Final_Project_2026.Lamas_Israel_2026` AS l
    LEFT JOIN supermarkets_by_city AS s
ON TRIM(l.city_name) = s.city_name_clean
WHERE l.total_population IS NOT NULL AND l.total_population > 0
    )

-- Scope A: All Israeli Settlements (Demonstrating true baseline distribution)
SELECT
    '1_All_Settlements (Incl. 0 Supermarkets)' AS analysis_scope,
    COUNT(*) AS total_settlements,

    -- Absolute Supermarket Count Metrics
    ROUND(AVG(supermarket_count), 2) AS mean_supermarkets,
    ROUND(STDDEV(supermarket_count), 2) AS sd_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(0)] AS min_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(1)] AS q1_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(2)] AS median_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(3)] AS q3_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(4)] AS max_supermarkets,
    (APPROX_QUANTILES(supermarket_count, 4)[OFFSET(3)] - APPROX_QUANTILES(supermarket_count, 4)[OFFSET(1)]) AS iqr_supermarkets,

    -- Supermarkets per 10k Residents Metrics
    ROUND(AVG(supermarkets_per_10k), 2) AS mean_per_10k,
    ROUND(STDDEV(supermarkets_per_10k), 2) AS sd_per_10k,
    APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(1)] AS q1_per_10k,
    APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(2)] AS median_per_10k,
    APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(3)] AS q3_per_10k,
    ROUND(
            APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(3)] - APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(1)],
            2
    ) AS iqr_per_10k
FROM lamas_supermarkets_merged

UNION ALL

-- Scope B: Active Retail Cities Only (Quantifying survivorship bias)
SELECT
    '2_Active_Retail_Cities_Only (>= 1 Supermarket)' AS analysis_scope,
    COUNT(*) AS total_settlements,

    ROUND(AVG(supermarket_count), 2) AS mean_supermarkets,
    ROUND(STDDEV(supermarket_count), 2) AS sd_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(0)] AS min_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(1)] AS q1_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(2)] AS median_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(3)] AS q3_supermarkets,
    APPROX_QUANTILES(supermarket_count, 4)[OFFSET(4)] AS max_supermarkets,
    (APPROX_QUANTILES(supermarket_count, 4)[OFFSET(3)] - APPROX_QUANTILES(supermarket_count, 4)[OFFSET(1)]) AS iqr_supermarkets,

    ROUND(AVG(supermarkets_per_10k), 2) AS mean_per_10k,
    ROUND(STDDEV(supermarkets_per_10k), 2) AS sd_per_10k,
    APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(1)] AS q1_per_10k,
    APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(2)] AS median_per_10k,
    APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(3)] AS q3_per_10k,
    ROUND(
            APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(3)] - APPROX_QUANTILES(supermarkets_per_10k, 4)[OFFSET(1)],
            2
    ) AS iqr_per_10k
FROM lamas_supermarkets_merged
WHERE supermarket_count > 0;

-- ==============================================================================
-- Query 2: Benchmarking Yavne & City-Level Retail Saturation (Cities >= 20k)
-- ==============================================================================
WITH supermarkets_by_city AS (
    SELECT
        TRIM(city) AS city_name_clean,
        COUNT(DISTINCT id) AS supermarket_count
    FROM `bqproj26.Final_Project_2026.supermarkets_il`
    WHERE city IS NOT NULL AND TRIM(city) != ''
GROUP BY TRIM(city)
    ),

    city_metrics AS (
SELECT
    l.city_id,
    TRIM(l.city_name) AS city_name,
    l.napa,
    l.total_population,
    COALESCE(s.supermarket_count, 0) AS supermarket_count,
    ROUND(
    SAFE_DIVIDE(COALESCE(s.supermarket_count, 0) * 10000.0, l.total_population),
    2
    ) AS supermarkets_per_10k
FROM `bqproj26.Final_Project_2026.Lamas_Israel_2026` AS l
    LEFT JOIN supermarkets_by_city AS s
ON TRIM(l.city_name) = s.city_name_clean
WHERE l.total_population >= 20000
    ),

    ranked_cities AS (
SELECT
    *,
    ROUND(PERCENT_RANK() OVER (ORDER BY supermarkets_per_10k ASC) * 100, 1) AS density_percentile,
    NTILE(4) OVER (ORDER BY supermarkets_per_10k ASC) AS density_quartile,
    ROUND(
    SAFE_DIVIDE(
    supermarkets_per_10k - AVG(supermarkets_per_10k) OVER (),
    STDDEV(supermarkets_per_10k) OVER ()
    ),
    2
    ) AS z_score_per_10k
FROM city_metrics
    )

SELECT
    city_id,
    city_name,
    napa,
    total_population,
    supermarket_count,
    supermarkets_per_10k,
    density_percentile,
    density_quartile,
    z_score_per_10k,
    CASE
        WHEN city_name = 'יבנה' THEN '0_TARGET_BRANCH_YAVNE'
        WHEN density_quartile = 4 THEN '1_HIGH_SATURATION (Q4)'
        WHEN density_quartile = 1 THEN '2_UNDERSERVED_OPPORTUNITY (Q1)'
        ELSE '3_MODERATE_COMPETITION (Q2-Q3)'
        END AS market_status
FROM ranked_cities
ORDER BY
    CASE WHEN city_name = 'יבנה' THEN 0 ELSE 1 END ASC,
    supermarkets_per_10k DESC;