/* ==============================================================================
   File: 07_part4_linear_regressions.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Part 4 (15%): Linear Regression Models & Trend Line Data
     * Query 4A: Regression 1 - Weekly Unique Customer Devices vs. Week Number
     * Query 4B: Regression 2 - Purchase Amount (`total`) vs. Dwell Time (`dwell_minutes`)
                 + New Calculated Variable (`dwell_minutes / total`)
     * Query 4C: Minute-by-Minute Aggregation (1..141 min) for Regression 2 Bonus Plot
   ============================================================================== */

-- ==============================================================================
-- Query 4A: Regression 1 Dataset & OLS Metrics (Unique Customer Devices by Week)
-- ==============================================================================
WITH weekly_customer_series AS (
  SELECT
    -- Truncate timestamp to Sunday-based week start date
    DATE_TRUNC(DATE(timestamp), WEEK(SUNDAY)) AS week_start_date,
    MIN(DATE(timestamp)) AS first_active_date_in_week,
    MAX(DATE(timestamp)) AS last_active_date_in_week,
    COUNT(DISTINCT DATE(timestamp)) AS active_operating_days,
    
    -- Y1 (Primary): All unique customer devices (repeat + one_time + not_paying)
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id END) AS unique_customer_devices_all,
    
    -- Y2 (Clean Signal <= 30m): Unique customer devices with valid accuracy
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') AND accuracy_m <= 30 THEN device_id END) AS unique_customer_devices_clean,
    
    -- Y3 (Paying App Customers Only): repeat_customer + one_time_customer
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer') THEN device_id END) AS unique_paying_customer_devices,
    
    -- Segment Breakdown per Week
    COUNT(DISTINCT CASE WHEN role = 'repeat_customer' THEN device_id END) AS repeat_devices,
    COUNT(DISTINCT CASE WHEN role = 'one_time_customer' THEN device_id END) AS onetime_devices,
    COUNT(DISTINCT CASE WHEN role = 'not_paying' THEN device_id END) AS nonpaying_devices,
    COUNTIF(role IN ('repeat_customer', 'one_time_customer', 'not_paying')) AS total_customer_pings
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY week_start_date
),

indexed_weeks AS (
  SELECT
    -- Independent Variable (X): Sequential Week Number (1 to N)
    ROW_NUMBER() OVER (ORDER BY week_start_date ASC) AS week_number,
    week_start_date,
    first_active_date_in_week,
    last_active_date_in_week,
    active_operating_days,
    unique_customer_devices_all,
    unique_customer_devices_clean,
    unique_paying_customer_devices,
    repeat_devices,
    onetime_devices,
    nonpaying_devices,
    total_customer_pings
  FROM weekly_customer_series
),

reg1_ols_stats AS (
  -- Calculate OLS Linear Regression parameters (Y = unique_customer_devices_all, X = week_number)
  SELECT
    COUNT(*) AS n_weeks,
    COVAR_SAMP(unique_customer_devices_all, week_number) / VAR_SAMP(week_number) AS slope_b1,
    AVG(unique_customer_devices_all) - (COVAR_SAMP(unique_customer_devices_all, week_number) / VAR_SAMP(week_number)) * AVG(week_number) AS intercept_b0,
    CORR(unique_customer_devices_all, week_number) AS pearson_r,
    POW(CORR(unique_customer_devices_all, week_number), 2) AS r_squared
  FROM indexed_weeks
)

SELECT
  w.*,
  -- Predicted Y value from the OLS Trend Line: Y_hat = b0 + b1 * week_number
  ROUND(s.intercept_b0 + s.slope_b1 * w.week_number, 2) AS trend_line_predicted_devices,
  ROUND(s.slope_b1, 4) AS model_slope_b1,
  ROUND(s.intercept_b0, 2) AS model_intercept_b0,
  ROUND(s.pearson_r, 4) AS model_pearson_r,
  ROUND(s.r_squared, 4) AS model_r_squared
FROM indexed_weeks AS w
CROSS JOIN reg1_ols_stats AS s
ORDER BY w.week_number ASC;


-- ==============================================================================
-- Query 4B: Regression 2 OLS Summary (`total` vs. `dwell_minutes`) 
--           + New Calculated Variable (`dwell_minutes / total`)
-- ==============================================================================
WITH app_sales_enriched AS (
  SELECT
    s.sale_id,
    s.customer_id,
    COALESCE(g.role, 'app_customer') AS customer_segment,
    CAST(s.dwell_minutes AS FLOAT64) AS x_dwell_minutes,
    CAST(s.total AS FLOAT64) AS y_total_ils,
    
    -- Required New Calculated Variable: Dwell Time (min) divided by Purchase Amount (ILS)
    SAFE_DIVIDE(s.dwell_minutes, s.total) AS dwell_min_per_ils,
    
    -- Inverse Efficiency Metric: Purchase Amount (ILS) divided by Dwell Time (min)
    SAFE_DIVIDE(s.total, s.dwell_minutes) AS ils_per_dwell_min
  FROM `bqproj26.Final_Project_2026.log_sales` AS s
  LEFT JOIN (
    SELECT DISTINCT device_id, role
    FROM `bqproj26.Final_Project_2026.geolocation`
  ) AS g
    ON s.customer_id = g.device_id
  -- Hints 1 & 2: Keep only App Customers where dwell_minutes is NOT NULL
  WHERE s.customer_id IS NOT NULL
    AND s.dwell_minutes IS NOT NULL
    AND s.total IS NOT NULL
),

reg2_grouped_stats AS (
  SELECT
    IFNULL(customer_segment, '0_ALL_APP_CUSTOMERS (Combined)') AS model_scope,
    COUNT(*) AS n_transactions,
    
    -- X (dwell_minutes) & Y (total) Descriptive Stats
    ROUND(AVG(x_dwell_minutes), 2) AS mean_x_dwell_min,
    ROUND(STDDEV_SAMP(x_dwell_minutes), 2) AS sd_x_dwell_min,
    ROUND(AVG(y_total_ils), 2) AS mean_y_total_ils,
    ROUND(STDDEV_SAMP(y_total_ils), 2) AS sd_y_total_ils,
    
    -- New Calculated Variable Stats (`dwell_minutes / total`)
    ROUND(AVG(dwell_min_per_ils), 4) AS mean_dwell_min_per_ils,
    ROUND(STDDEV_SAMP(dwell_min_per_ils), 4) AS sd_dwell_min_per_ils,
    ROUND(APPROX_QUANTILES(dwell_min_per_ils, 100)[OFFSET(50)], 4) AS median_dwell_min_per_ils,
    ROUND(AVG(ils_per_dwell_min), 2) AS mean_ils_per_dwell_min,
    
    -- OLS Regression Core Parameters: Slope (b1), Intercept (b0), r, R^2
    COVAR_SAMP(y_total_ils, x_dwell_minutes) / VAR_SAMP(x_dwell_minutes) AS raw_slope_b1,
    AVG(y_total_ils) - (COVAR_SAMP(y_total_ils, x_dwell_minutes) / VAR_SAMP(x_dwell_minutes)) * AVG(x_dwell_minutes) AS raw_intercept_b0,
    CORR(y_total_ils, x_dwell_minutes) AS raw_pearson_r,
    POW(CORR(y_total_ils, x_dwell_minutes), 2) AS raw_r_squared
  FROM app_sales_enriched
  GROUP BY ROLLUP(customer_segment)
)

SELECT
  model_scope,
  n_transactions,
  mean_x_dwell_min,
  sd_x_dwell_min,
  mean_y_total_ils,
  sd_y_total_ils,
  
  -- New Calculated Variable (`dwell_minutes / total`) & Inverse (`total / dwell_minutes`)
  mean_dwell_min_per_ils,
  sd_dwell_min_per_ils,
  median_dwell_min_per_ils,
  mean_ils_per_dwell_min,
  
  -- Linear Regression Equation & Goodness-of-Fit Metrics
  ROUND(raw_slope_b1, 4) AS slope_b1_ils_per_min,
  ROUND(raw_intercept_b0, 4) AS intercept_b0_ils,
  ROUND(raw_pearson_r, 4) AS pearson_r,
  ROUND(raw_r_squared, 4) AS r_squared,
  
  -- Hypothesis Testing Metrics: t-statistic & F-statistic (df = n - 2)
  ROUND(
    SAFE_DIVIDE(
      raw_pearson_r * SQRT(n_transactions - 2),
      SQRT(1.0 - raw_r_squared)
    ),
    2
  ) AS t_statistic,
  ROUND(
    SAFE_DIVIDE(
      raw_r_squared * (n_transactions - 2),
      1.0 - raw_r_squared
    ),
    2
  ) AS f_statistic
FROM reg2_grouped_stats
ORDER BY model_scope ASC;


-- ==============================================================================
-- Query 4C: Minute-Level Aggregation (1..141 min) for Regression 2 Bonus Trend Plot
-- ==============================================================================
SELECT
  CAST(dwell_minutes AS INT64) AS dwell_minutes,
  COUNT(*) AS tx_count,
  ROUND(AVG(total), 2) AS mean_total_ils,
  ROUND(STDDEV(total), 2) AS sd_total_ils,
  ROUND(MIN(total), 2) AS min_total_ils,
  ROUND(APPROX_QUANTILES(total, 4)[OFFSET(1)], 2) AS q1_total_ils,
  ROUND(APPROX_QUANTILES(total, 4)[OFFSET(2)], 2) AS median_total_ils,
  ROUND(APPROX_QUANTILES(total, 4)[OFFSET(3)], 2) AS q3_total_ils,
  ROUND(MAX(total), 2) AS max_total_ils,
  ROUND(AVG(SAFE_DIVIDE(dwell_minutes, total)), 4) AS mean_dwell_min_per_ils,
  ROUND(AVG(SAFE_DIVIDE(total, dwell_minutes)), 2) AS mean_ils_per_min
FROM `bqproj26.Final_Project_2026.log_sales`
WHERE customer_id IS NOT NULL
  AND dwell_minutes IS NOT NULL
GROUP BY CAST(dwell_minutes AS INT64)
ORDER BY dwell_minutes ASC;
