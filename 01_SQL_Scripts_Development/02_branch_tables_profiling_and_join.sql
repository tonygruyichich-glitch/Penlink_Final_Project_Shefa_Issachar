/* ==============================================================================
   File: 02_branch_tables_profiling_and_join.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Author: Tony Gruyichich
   Description: Part 1 - Data profiling, quality audit, and entity-level merging
                of branch core tables (`log_sales` and `geolocation`).
   ============================================================================== */

-- ==============================================================================
-- Query 1: Profile `log_sales` - Volume, Date Range, App Adoption, and Sanity Checks
-- ==============================================================================
SELECT
    COUNT(*) AS total_transactions,
    COUNT(DISTINCT sale_id) AS unique_sale_ids,
    MIN(timestamp) AS first_transaction_ts,
    MAX(timestamp) AS last_transaction_ts,

    -- App vs. Non-App Customers Breakdown
    COUNTIF(customer_id IS NOT NULL) AS app_transactions,
    COUNTIF(customer_id IS NULL) AS non_app_transactions,
    ROUND(SAFE_DIVIDE(COUNTIF(customer_id IS NOT NULL) * 100.0, COUNT(*)), 2) AS pct_app_transactions,
    COUNT(DISTINCT customer_id) AS unique_app_customers,

    -- Sanity checks on Revenue (`total`) and Dwell Time (`dwell_minutes`)
    ROUND(MIN(total), 2) AS min_total_ils,
    ROUND(AVG(total), 2) AS mean_total_ils,
    ROUND(MAX(total), 2) AS max_total_ils,
    COUNTIF(total <= 0 OR total IS NULL) AS invalid_total_rows,

    ROUND(MIN(dwell_minutes), 2) AS min_dwell_min,
    ROUND(AVG(dwell_minutes), 2) AS mean_dwell_min,
    ROUND(MAX(dwell_minutes), 2) AS max_dwell_min,
    COUNTIF(dwell_minutes IS NULL) AS null_dwell_rows
FROM `bqproj26.Final_Project_2026.log_sales`;

-- ==============================================================================
-- Query 2: Profile `geolocation` Roles, Accuracy Anomalies, and Merge with `log_sales`
-- ==============================================================================
WITH customer_sales_summary AS (
    SELECT
        customer_id,
        COUNT(DISTINCT sale_id) AS total_purchases,
        ROUND(SUM(total), 2) AS total_spent_ils,
        ROUND(AVG(total), 2) AS avg_basket_ils,
        ROUND(AVG(dwell_minutes), 1) AS avg_dwell_minutes
    FROM `bqproj26.Final_Project_2026.log_sales`
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
),

     device_geo_summary AS (
         SELECT
             device_id,
             role,
             COUNT(*) AS total_pings,
             COUNT(DISTINCT DATE(timestamp)) AS active_days,
             ROUND(MIN(accuracy_m), 2) AS min_accuracy_m,
             ROUND(AVG(accuracy_m), 2) AS avg_accuracy_m,
             ROUND(MAX(accuracy_m), 2) AS max_accuracy_m,
             COUNTIF(accuracy_m > 30) AS noisy_pings_over_30m
         FROM `bqproj26.Final_Project_2026.geolocation`
         GROUP BY device_id, role
     )

SELECT
    g.role,
    COUNT(DISTINCT g.device_id) AS unique_devices,
    COUNT(DISTINCT s.customer_id) AS matched_buyers_in_sales,
    SUM(g.total_pings) AS total_geo_pings,
    ROUND(AVG(g.active_days), 1) AS avg_active_days_per_person,

    -- Accuracy & Noise Profiling per Role
    ROUND(MIN(g.min_accuracy_m), 2) AS min_acc_m,
    ROUND(AVG(g.avg_accuracy_m), 2) AS mean_acc_m,
    ROUND(MAX(g.max_accuracy_m), 2) AS max_acc_m,
    SUM(g.noisy_pings_over_30m) AS total_pings_over_30m,
    ROUND(SAFE_DIVIDE(SUM(g.noisy_pings_over_30m) * 100.0, SUM(g.total_pings)), 2) AS pct_noisy_pings,

    -- Merged Sales & Basket Metrics from `log_sales`
    COALESCE(SUM(s.total_purchases), 0) AS total_sales_tx,
    ROUND(AVG(s.total_purchases), 1) AS avg_tx_per_buyer,
    ROUND(AVG(s.avg_basket_ils), 2) AS avg_basket_ils,
    ROUND(AVG(s.avg_dwell_minutes), 1) AS avg_dwell_min
FROM device_geo_summary AS g
         LEFT JOIN customer_sales_summary AS s
                   ON g.device_id = s.customer_id
GROUP BY g.role
ORDER BY total_geo_pings DESC;
