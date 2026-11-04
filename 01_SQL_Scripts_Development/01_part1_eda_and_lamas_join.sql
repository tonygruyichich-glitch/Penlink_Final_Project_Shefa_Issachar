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



/* ==============================================================================
   Summary Metric 2: Hourly Unique Customer Traffic (Central Tendency & Dispersion)
    analytical Goal: Identify true operating hours, peak congestion windows, and
                    compare customer presence vs. staff presence across the day.
   ============================================================================== */

-- Step 1: Count unique customers and staff per specific Date AND Hour
WITH daily_hourly_traffic AS (
    SELECT
    DATE(timestamp) AS visit_date,
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,

-- Count unique customer devices (excluding employees and suppliers)
    COUNT(DISTINCT CASE
    WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id
    END) AS unique_customers,

-- Count unique paying vs. non-paying visitors for conversion context
    COUNT(DISTINCT CASE
    WHEN role IN ('repeat_customer', 'one_time_customer') THEN device_id
    END) AS unique_paying_customers,

-- Count unique staff members present in that hour
    COUNT(DISTINCT CASE
    WHEN role NOT IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id
    END) AS unique_staff
FROM `bqproj26.Final_Project_2026.geolocation`
-- Keep clean signal pings (<= 30m) to avoid false perimeter detections
WHERE accuracy_m <= 30
GROUP BY
    visit_date,
    hour_of_day
    )

-- Step 2: Aggregate across all active days to compute hourly Mean, SD, Median, and IQR
SELECT
    hour_of_day,
    COUNT(DISTINCT visit_date) AS active_days_observed,

    -- Customer Traffic: Central Tendency & Dispersion
    ROUND(AVG(unique_customers), 2) AS mean_customers,
    ROUND(STDDEV(unique_customers), 2) AS sd_customers,
    APPROX_QUANTILES(unique_customers, 4)[OFFSET(0)] AS min_customers,
    APPROX_QUANTILES(unique_customers, 4)[OFFSET(1)] AS q1_customers,
    APPROX_QUANTILES(unique_customers, 4)[OFFSET(2)] AS median_customers,
    APPROX_QUANTILES(unique_customers, 4)[OFFSET(3)] AS q3_customers,
    APPROX_QUANTILES(unique_customers, 4)[OFFSET(4)] AS max_customers,
    (APPROX_QUANTILES(unique_customers, 4)[OFFSET(3)] - APPROX_QUANTILES(unique_customers, 4)[OFFSET(1)]) AS iqr_customers,

    -- Staff Presence Benchmark
    ROUND(AVG(unique_staff), 2) AS mean_staff_present,

    -- Customer-to-Staff Ratio (Operational Load Indicator)
    ROUND(SAFE_DIVIDE(AVG(unique_customers), AVG(unique_staff)), 2) AS customers_per_staff_ratio
FROM daily_hourly_traffic
GROUP BY hour_of_day
ORDER BY hour_of_day ASC;




/* ==============================================================================
   Summary Metric 3: Basket Revenue (`total`), Dwell Time (`dwell_minutes`), and
                     Spend Velocity (`ils_per_minute`) by Segment & Payment Method
   ============================================================================== */

-- Step 1: Extract unique customer-to-role mapping from `geolocation` (1 row per device)
WITH unique_device_roles AS (
    SELECT DISTINCT
        device_id,
        role
    FROM `bqproj26.Final_Project_2026.geolocation`
),

-- Step 2: Enrich `log_sales` with customer segment and engineered Spend Velocity metric
     enriched_sales AS (
         SELECT
             s.sale_id,
             s.timestamp,
             s.customer_id,
             COALESCE(g.role, 'no_phone_anonymous') AS customer_segment,
             s.payment_method,
             s.total,
             s.dwell_minutes,
             -- Engineered Feature: Spend Velocity (ILS spent per minute inside the store)
             ROUND(SAFE_DIVIDE(s.total, s.dwell_minutes), 2) AS ils_per_minute
         FROM `bqproj26.Final_Project_2026.log_sales` AS s
                  LEFT JOIN unique_device_roles AS g
                            ON s.customer_id = g.device_id
     )

-- Step 3A: Summary Statistics by Customer Segment
SELECT
    '1_By_Customer_Segment' AS breakdown_dimension,
    customer_segment AS category,
    COUNT(*) AS transactions_count,
    ROUND(SAFE_DIVIDE(COUNT(*) * 100.0, SUM(COUNT(*)) OVER ()), 2) AS pct_of_transactions,
    ROUND(SUM(total), 2) AS total_revenue_ils,
    ROUND(SAFE_DIVIDE(SUM(total) * 100.0, SUM(SUM(total)) OVER ()), 2) AS pct_of_revenue,

    -- Basket Size (`total` ILS): Central Tendency & Dispersion
    ROUND(AVG(total), 2) AS mean_basket_ils,
    ROUND(STDDEV(total), 2) AS sd_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(1)], 2) AS q1_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(2)], 2) AS median_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(3)], 2) AS q3_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(3)] - APPROX_QUANTILES(total, 4)[OFFSET(1)], 2) AS iqr_basket_ils,

    -- Dwell Time (`dwell_minutes`): Central Tendency & Dispersion
    ROUND(AVG(dwell_minutes), 1) AS mean_dwell_min,
    ROUND(STDDEV(dwell_minutes), 1) AS sd_dwell_min,
    APPROX_QUANTILES(dwell_minutes, 4)[OFFSET(2)] AS median_dwell_min,
    (APPROX_QUANTILES(dwell_minutes, 4)[OFFSET(3)] - APPROX_QUANTILES(dwell_minutes, 4)[OFFSET(1)]) AS iqr_dwell_min,

    -- Engineered Metric: Spend Velocity (ILS per Minute)
    ROUND(AVG(ils_per_minute), 2) AS mean_ils_per_min,
    ROUND(APPROX_QUANTILES(ils_per_minute, 4)[OFFSET(2)], 2) AS median_ils_per_min
FROM enriched_sales
GROUP BY customer_segment

UNION ALL

-- Step 3B: Summary Statistics by Payment Method
SELECT
    '2_By_Payment_Method' AS breakdown_dimension,
    payment_method AS category,
    COUNT(*) AS transactions_count,
    ROUND(SAFE_DIVIDE(COUNT(*) * 100.0, SUM(COUNT(*)) OVER ()), 2) AS pct_of_transactions,
    ROUND(SUM(total), 2) AS total_revenue_ils,
    ROUND(SAFE_DIVIDE(SUM(total) * 100.0, SUM(SUM(total)) OVER ()), 2) AS pct_of_revenue,

    ROUND(AVG(total), 2) AS mean_basket_ils,
    ROUND(STDDEV(total), 2) AS sd_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(1)], 2) AS q1_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(2)], 2) AS median_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(3)], 2) AS q3_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(3)] - APPROX_QUANTILES(total, 4)[OFFSET(1)], 2) AS iqr_basket_ils,

    ROUND(AVG(dwell_minutes), 1) AS mean_dwell_min,
    ROUND(STDDEV(dwell_minutes), 1) AS sd_dwell_min,
    APPROX_QUANTILES(dwell_minutes, 4)[OFFSET(2)] AS median_dwell_min,
    (APPROX_QUANTILES(dwell_minutes, 4)[OFFSET(3)] - APPROX_QUANTILES(dwell_minutes, 4)[OFFSET(1)]) AS iqr_dwell_min,

    ROUND(AVG(ils_per_minute), 2) AS mean_ils_per_min,
    ROUND(APPROX_QUANTILES(ils_per_minute, 4)[OFFSET(2)], 2) AS median_ils_per_min
FROM enriched_sales
GROUP BY payment_method
ORDER BY
    breakdown_dimension ASC,
    total_revenue_ils DESC;