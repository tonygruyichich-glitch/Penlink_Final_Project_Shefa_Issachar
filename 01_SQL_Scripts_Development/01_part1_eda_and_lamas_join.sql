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






/* ==============================================================================
   Part 1 - Univariate Chart 1: Distribution of `accuracy_m` (Suspicious Outlier Tail)
   Analytical Goal: Examine the single-variable frequency distribution of GPS/WiFi
                    accuracy (`accuracy_m`) to visually justify the 30m outlier threshold.
   ============================================================================== */

WITH accuracy_binned AS (
    SELECT
        -- Group continuous accuracy_m into ordered 5-meter bins up to 40m, plus outlier buckets
        CASE
            WHEN accuracy_m <= 5  THEN '01_01-05m (High Precision)'
            WHEN accuracy_m <= 10 THEN '02_06-10m (High Precision)'
            WHEN accuracy_m <= 15 THEN '03_11-15m (Good Precision)'
            WHEN accuracy_m <= 20 THEN '04_16-20m (Moderate)'
            WHEN accuracy_m <= 25 THEN '05_21-25m (Moderate)'
            WHEN accuracy_m <= 30 THEN '06_26-30m (Threshold Limit)'
            WHEN accuracy_m <= 35 THEN '07_31-35m (Noisy Drift)'
            WHEN accuracy_m <= 40 THEN '08_36-40m (Noisy Drift)'
            WHEN accuracy_m <= 45 THEN '09_41-45m (Edge Drift)'
            ELSE '10_46-150m (Severe Anomaly / Security)'
            END AS accuracy_bin,
        COUNT(*) AS ping_count
    FROM `bqproj26.Final_Project_2026.geolocation`
    WHERE accuracy_m IS NOT NULL
    GROUP BY accuracy_bin
)

SELECT
    accuracy_bin,
    ping_count,
    -- Share of total pings in each bin
    ROUND(SAFE_DIVIDE(ping_count * 100.0, SUM(ping_count) OVER ()), 2) AS pct_of_total_pings,
    -- Cumulative Distribution Function (CDF) using a Window Function
    ROUND(
            SAFE_DIVIDE(
                    SUM(ping_count) OVER (ORDER BY accuracy_bin ASC) * 100.0,
                    SUM(ping_count) OVER ()
            ),
            2
    ) AS cumulative_pct
FROM accuracy_binned
ORDER BY accuracy_bin ASC;





/* ==============================================================================
   Part 1 - Univariate Chart 2: Distribution of Transaction Basket Value (`total`)
   Analytical Goal: Analyze the single-variable distribution of transaction revenue
                    (`total` in ILS) across 100-ILS bins to uncover mixture modes,
                    right-skewness, and revenue concentration.
   ============================================================================== */

WITH basket_binned AS (
    SELECT
        -- Mathematical binning into 100-ILS intervals using FLOOR()
        CAST(FLOOR(total / 100.0) * 100 AS INT64) AS bin_floor_ils,
        COUNT(*) AS tx_count,
        ROUND(SUM(total), 2) AS bin_revenue_ils,
        -- Track composition within each basket tier (App vs. No-Phone)
        COUNTIF(customer_id IS NOT NULL) AS app_tx_count,
        COUNTIF(customer_id IS NULL) AS no_phone_tx_count
    FROM `bqproj26.Final_Project_2026.log_sales`
    WHERE total IS NOT NULL AND total > 0
    GROUP BY bin_floor_ils
)

SELECT
    -- Format clean interval label (e.g., '0100-0199 ILS')
    CONCAT(
            LPAD(CAST(bin_floor_ils AS STRING), 4, '0'),
            '-',
            LPAD(CAST(bin_floor_ils + 99 AS STRING), 4, '0'),
            ' ILS'
    ) AS basket_range_ils,
    bin_floor_ils,
    tx_count,
    ROUND(SAFE_DIVIDE(tx_count * 100.0, SUM(tx_count) OVER ()), 2) AS pct_of_transactions,
    ROUND(
            SAFE_DIVIDE(
                    SUM(tx_count) OVER (ORDER BY bin_floor_ils ASC) * 100.0,
                    SUM(tx_count) OVER ()
            ),
            2
    ) AS cumulative_tx_pct,

    -- Revenue share contributed by each basket bin
    bin_revenue_ils,
    ROUND(SAFE_DIVIDE(bin_revenue_ils * 100.0, SUM(bin_revenue_ils) OVER ()), 2) AS pct_of_revenue,
    ROUND(
            SAFE_DIVIDE(
                    SUM(bin_revenue_ils) OVER (ORDER BY bin_floor_ils ASC) * 100.0,
                    SUM(bin_revenue_ils) OVER ()
            ),
            2
    ) AS cumulative_revenue_pct,

    -- Share of anonymous (no-phone) transactions inside each basket bin
    ROUND(SAFE_DIVIDE(no_phone_tx_count * 100.0, tx_count), 1) AS pct_no_phone_in_bin
FROM basket_binned
ORDER BY bin_floor_ils ASC;





/* ==============================================================================
   Part 1 - Univariate Chart 3: Distribution of Customer Dwell Time (`dwell_minutes`)
   Analytical Goal: Examine the single-variable distribution of store dwell time
                    in 10-minute intervals, quantify the structural NULL share
                    (no-app shoppers), and identify prolonged stay tails (>90 min).
   ============================================================================== */

WITH dwell_binned AS (
    SELECT
        -- Group NULLs separately and bin valid dwell_minutes into 10-minute intervals
        CASE
            WHEN dwell_minutes IS NULL THEN -1
            ELSE CAST(FLOOR(dwell_minutes / 10.0) * 10 AS INT64)
            END AS bin_floor_min,
        COUNT(*) AS tx_count,
        ROUND(AVG(total), 2) AS avg_basket_in_bin_ils
    FROM `bqproj26.Final_Project_2026.log_sales`
    GROUP BY bin_floor_min
)

SELECT
    CASE
        WHEN bin_floor_min = -1 THEN '00_NULL (No-App Customer)'
        ELSE CONCAT(
                LPAD(CAST(bin_floor_min AS STRING), 3, '0'),
                '-',
                LPAD(CAST(bin_floor_min + 9 AS STRING), 3, '0'),
                ' Min'
             )
        END AS dwell_range_min,
    bin_floor_min,
    tx_count,
    -- Percentage out of ALL 34,589 transactions (including NULLs)
    ROUND(SAFE_DIVIDE(tx_count * 100.0, SUM(tx_count) OVER ()), 2) AS pct_of_all_tx,

    -- Percentage out of VALID app transactions only (30,993 rows where dwell_minutes IS NOT NULL)
    ROUND(
            CASE
                WHEN bin_floor_min = -1 THEN NULL
                ELSE SAFE_DIVIDE(
                        tx_count * 100.0,
                        SUM(CASE WHEN bin_floor_min >= 0 THEN tx_count ELSE 0 END) OVER ()
                     )
                END,
            2
    ) AS pct_of_valid_app_tx,

    -- Cumulative % across valid app transactions
    ROUND(
            CASE
                WHEN bin_floor_min = -1 THEN NULL
                ELSE SAFE_DIVIDE(
                        SUM(CASE WHEN bin_floor_min >= 0 THEN tx_count ELSE 0 END) OVER (ORDER BY bin_floor_min ASC) * 100.0,
                        SUM(CASE WHEN bin_floor_min >= 0 THEN tx_count ELSE 0 END) OVER ()
                     )
                END,
            2
    ) AS cumulative_valid_pct,

    avg_basket_in_bin_ils
FROM dwell_binned
ORDER BY bin_floor_min ASC;




/* ==============================================================================
   Part 1 - Multivariate Chart 1 (3 Variables):
   Hour of Day x Day of Week x Unique Customer Devices
   Analytical Goal: Build a 2D spatiotemporal traffic matrix (Day of Week x Hour)
                    to uncover weekday vs. Thursday/Friday behavioral patterns,
                    peak congestion windows, and "dead zones".
   ============================================================================== */

-- Step 1: Count unique customer devices per specific calendar date and hour
WITH daily_hourly_customer_counts AS (
    SELECT
    DATE(timestamp) AS visit_date,
    EXTRACT(DAYOFWEEK FROM DATE(timestamp)) AS day_of_week_num, -- 1=Sun, 2=Mon, ..., 6=Fri, 7=Sat
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,
    COUNT(DISTINCT device_id) AS unique_customer_devices,
    COUNT(DISTINCT CASE WHEN role = 'repeat_customer' THEN device_id END) AS repeat_customers,
    COUNT(DISTINCT CASE WHEN role = 'one_time_customer' THEN device_id END) AS one_time_customers,
    COUNT(DISTINCT CASE WHEN role = 'not_paying' THEN device_id END) AS non_paying_visitors
FROM `bqproj26.Final_Project_2026.geolocation`
WHERE role IN ('repeat_customer', 'one_time_customer', 'not_paying')
  AND accuracy_m <= 30
GROUP BY
    visit_date,
    day_of_week_num,
    hour_of_day
    )

-- Step 2: Aggregate across dates to get Mean & Median customers per (Day of Week x Hour)
SELECT
    day_of_week_num,
    CASE day_of_week_num
        WHEN 1 THEN '1_Sunday (ראשון)'
        WHEN 2 THEN '2_Monday (שני)'
        WHEN 3 THEN '3_Tuesday (שלישי)'
        WHEN 4 THEN '4_Wednesday (רביעי)'
        WHEN 5 THEN '5_Thursday (חמישי)'
        WHEN 6 THEN '6_Friday (שישי)'
        WHEN 7 THEN '7_Saturday (שבת)'
        END AS day_name,
    hour_of_day,
    COUNT(DISTINCT visit_date) AS active_days_sampled,

    -- Central Tendency & Peak Metrics for Customer Devices
    ROUND(AVG(unique_customer_devices), 2) AS mean_customer_devices,
    APPROX_QUANTILES(unique_customer_devices, 4)[OFFSET(2)] AS median_customer_devices,
    MAX(unique_customer_devices) AS max_customer_devices,

    -- Segment Breakdown within each (Day x Hour) cell
    ROUND(AVG(repeat_customers), 2) AS mean_repeat_customers,
    ROUND(AVG(one_time_customers), 2) AS mean_one_time_customers,
    ROUND(AVG(non_paying_visitors), 2) AS mean_non_paying_visitors
FROM daily_hourly_customer_counts
GROUP BY
    day_of_week_num,
    day_name,
    hour_of_day
ORDER BY
    day_of_week_num ASC,
    hour_of_day ASC;




/* ==============================================================================
   Part 1 - Multivariate Chart 2 (3 Variables):
   Dwell Time (`dwell_minutes`) x Basket Value (`total`) x Customer Segment (`role`)
   Analytical Goal: Test whether the linear relationship between dwell time and
                    basket value differs across customer segments (Repeat vs. One-Time)
                    and payment types (Cards vs. Cash/Mobile).
   ============================================================================== */

WITH unique_customer_roles AS (
    SELECT DISTINCT
        device_id,
        role
    FROM `bqproj26.Final_Project_2026.geolocation`
),

     sales_with_segment AS (
         SELECT
             s.sale_id,
             s.total,
             s.dwell_minutes,
             CAST(FLOOR(s.dwell_minutes / 10.0) * 10 AS INT64) AS dwell_bin_10m,
             g.role AS customer_segment,
             CASE
                 WHEN s.payment_method IN ('credit_card', 'debit_card') THEN 'Card (Credit/Debit)'
                 ELSE 'Fast Pay (Mobile/Cash)'
                 END AS payment_group
         FROM `bqproj26.Final_Project_2026.log_sales` AS s
                  INNER JOIN unique_customer_roles AS g
                             ON s.customer_id = g.device_id
         WHERE s.dwell_minutes IS NOT NULL
           AND s.total IS NOT NULL
     )

SELECT
    dwell_bin_10m,
    CONCAT(
            LPAD(CAST(dwell_bin_10m AS STRING), 3, '0'),
            '-',
            LPAD(CAST(dwell_bin_10m + 9 AS STRING), 3, '0'),
            ' Min'
    ) AS dwell_interval,
    customer_segment,
    COUNT(*) AS tx_count,

    -- Basket Value Metrics per (Dwell Bin x Customer Segment)
    ROUND(AVG(total), 2) AS mean_basket_ils,
    ROUND(STDDEV(total), 2) AS sd_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(1)], 2) AS q1_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(2)], 2) AS median_basket_ils,
    ROUND(APPROX_QUANTILES(total, 4)[OFFSET(3)], 2) AS q3_basket_ils,

    -- Spend Velocity (ILS per Minute) within each cell
    ROUND(AVG(SAFE_DIVIDE(total, dwell_minutes)), 2) AS mean_ils_per_min,

    -- Share of Card Payments vs. Fast Pay within each (Dwell Bin x Segment)
    ROUND(SAFE_DIVIDE(COUNTIF(payment_group = 'Card (Credit/Debit)') * 100.0, COUNT(*)), 1) AS pct_card_payments
FROM sales_with_segment
GROUP BY
    dwell_bin_10m,
    dwell_interval,
    customer_segment
ORDER BY
    dwell_bin_10m ASC,
    customer_segment ASC;




/* ==============================================================================
   Part 1 - Multivariate Chart 3 (3 Variables):
   Store Zone (`area`) x Hour of Day (`hour_of_day`) x Customer & Staff Load
   Analytical Goal: Analyze the spatiotemporal flow of customers across store zones
                    (PARKING, SUPERMARKET, BUTCHERY, CASH_REGISTERS) by hour, and
                    quantify bottleneck ratios (Customers per Cashier / Butcher).
   ============================================================================== */

-- Step 1: Count unique customers and dedicated staff per Date, Hour, and Store Zone (`area`)
WITH daily_hourly_zone_load AS (
    SELECT
    DATE(timestamp) AS visit_date,
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,
    area,

-- Unique customers detected in this zone during this hour
    COUNT(DISTINCT CASE
    WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id
    END) AS zone_customers,

-- Total customer signal pings in this zone (measuring cumulative time/dwell volume)
    COUNTIF(role IN ('repeat_customer', 'one_time_customer', 'not_paying')) AS zone_customer_pings,

-- Dedicated staff present in this zone during this hour
    COUNT(DISTINCT CASE
    WHEN role NOT IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id
    END) AS zone_staff
FROM `bqproj26.Final_Project_2026.geolocation`
WHERE accuracy_m <= 30
  AND EXTRACT(HOUR FROM timestamp) BETWEEN 8 AND 20
GROUP BY
    visit_date,
    hour_of_day,
    area
    )

-- Step 2: Aggregate across active days (151 days) to get Mean Load per (Hour x Zone)
SELECT
    hour_of_day,
    area,
    COUNT(DISTINCT visit_date) AS active_days_with_zone_activity,

    -- Customer & Staff Presence Averages
    ROUND(AVG(zone_customers), 2) AS mean_zone_customers,
    APPROX_QUANTILES(zone_customers, 4)[OFFSET(2)] AS median_zone_customers,
    MAX(zone_customers) AS max_zone_customers,

    ROUND(AVG(zone_customer_pings), 1) AS mean_customer_pings_in_zone,
    ROUND(AVG(zone_staff), 2) AS mean_zone_staff,

    -- Operational Congestion Ratio: Customers per Staff Member inside that specific zone
    ROUND(SAFE_DIVIDE(AVG(zone_customers), AVG(zone_staff)), 2) AS zone_customers_per_staff
FROM daily_hourly_zone_load
WHERE area IN ('PARKING', 'SUPERMARKET', 'BUTCHERY', 'CASH_REGISTERS')
GROUP BY
    hour_of_day,
    area
ORDER BY
    hour_of_day ASC,
    CASE area
        WHEN 'PARKING' THEN 1
        WHEN 'SUPERMARKET' THEN 2
        WHEN 'BUTCHERY' THEN 3
        WHEN 'CASH_REGISTERS' THEN 4
        ELSE 5
        END ASC;