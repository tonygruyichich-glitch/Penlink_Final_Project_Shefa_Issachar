/* ==============================================================================
   File: 04_part2_data_quality_and_app_performance.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Part 2 - Task 3a & 3b: Signal Accuracy Outliers (`accuracy_m > 30`) 
                          and Empirical 40% App Ping Capture Rate Audit
   ============================================================================== */

-- ==============================================================================
-- Query 3A: Deep-Dive Audit of `accuracy_m > 30m` Outliers by Role & Store Area
-- ==============================================================================
WITH role_area_accuracy AS (
  SELECT
    role,
    area,
    COUNT(*) AS total_pings,
    COUNTIF(accuracy_m > 30) AS outlier_pings_gt_30m,
    COUNTIF(accuracy_m <= 30) AS valid_pings_le_30m,
    ROUND(MIN(accuracy_m), 2) AS min_acc_m,
    ROUND(AVG(accuracy_m), 2) AS mean_acc_m,
    ROUND(STDDEV(accuracy_m), 2) AS sd_acc_m,
    APPROX_QUANTILES(accuracy_m, 100)[OFFSET(50)] AS median_acc_m,
    APPROX_QUANTILES(accuracy_m, 100)[OFFSET(90)] AS p90_acc_m,
    ROUND(MAX(accuracy_m), 2) AS max_acc_m
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY role, area
)

SELECT
  role,
  area,
  total_pings,
  ROUND(SAFE_DIVIDE(total_pings * 100.0, SUM(total_pings) OVER ()), 2) AS pct_of_total_dataset,
  outlier_pings_gt_30m,
  valid_pings_le_30m,
  
  -- Within-Role Outlier Rate (% of this role+area's pings that exceed 30m)
  ROUND(SAFE_DIVIDE(outlier_pings_gt_30m * 100.0, total_pings), 2) AS outlier_rate_within_group_pct,
  
  -- Share of Total Dataset Outliers (% of all noisy pings in the entire branch)
  ROUND(SAFE_DIVIDE(outlier_pings_gt_30m * 100.0, SUM(outlier_pings_gt_30m) OVER ()), 2) AS share_of_all_outliers_pct,
  
  min_acc_m,
  mean_acc_m,
  sd_acc_m,
  median_acc_m,
  p90_acc_m,
  max_acc_m
FROM role_area_accuracy
ORDER BY outlier_rate_within_group_pct DESC, outlier_pings_gt_30m DESC;




-- ==============================================================================
-- Query 3B & 3C: Empirical Verification of the 40% App Capture Rate SLA
--                + Multi-Attribute Outlier Detection (Bonus 3c)
-- ==============================================================================
WITH daily_customer_pings AS (
  -- Step 1: Aggregate geolocation pings per customer and date (with zone & accuracy splits)
  SELECT
    device_id,
    DATE(timestamp) AS visit_date,
    ANY_VALUE(role) AS role,
    COUNT(*) AS total_visit_pings_all,
    COUNTIF(accuracy_m <= 30) AS total_visit_pings_clean,
    
    -- In-store vs. Parking breakdown (All Pings)
    COUNTIF(area IN ('SUPERMARKET', 'CASH_REGISTERS')) AS instore_pings_all,
    COUNTIF(area = 'PARKING') AS parking_pings_all,
    
    -- In-store vs. Parking breakdown (Clean Pings <= 30m)
    COUNTIF(area IN ('SUPERMARKET', 'CASH_REGISTERS') AND accuracy_m <= 30) AS instore_pings_clean,
    COUNTIF(area = 'PARKING' AND accuracy_m <= 30) AS parking_pings_clean,
    
    -- Empirical time span between first and last ping on that date (in minutes)
    TIMESTAMP_DIFF(MAX(timestamp), MIN(timestamp), MINUTE) + 1 AS empirical_geo_span_min
  FROM `bqproj26.Final_Project_2026.geolocation`
  WHERE role IN ('repeat_customer', 'one_time_customer')
  GROUP BY device_id, DATE(timestamp)
),

matched_visit_performance AS (
  -- Step 2: Join `log_sales` visits with daily geolocation pings
  SELECT
    s.sale_id,
    s.customer_id,
    DATE(s.timestamp) AS sale_date,
    EXTRACT(HOUR FROM s.timestamp) AS sale_hour,
    g.role AS customer_segment,
    s.total AS basket_ils,
    s.dwell_minutes,
    g.empirical_geo_span_min,
    
    COALESCE(g.total_visit_pings_all, 0) AS total_visit_pings_all,
    COALESCE(g.total_visit_pings_clean, 0) AS total_visit_pings_clean,
    COALESCE(g.instore_pings_all, 0) AS instore_pings_all,
    COALESCE(g.instore_pings_clean, 0) AS instore_pings_clean,
    COALESCE(g.parking_pings_all, 0) AS parking_pings_all,
    
    -- Capture Rate 1: All Visit Pings (Parking + Store) / dwell_minutes
    SAFE_DIVIDE(COALESCE(g.total_visit_pings_all, 0) * 100.0, s.dwell_minutes) AS capture_rate_all_vs_dwell_pct,
    
    -- Capture Rate 2: In-Store Pings Only (Supermarket + Cash Reg) / dwell_minutes
    SAFE_DIVIDE(COALESCE(g.instore_pings_all, 0) * 100.0, s.dwell_minutes) AS capture_rate_instore_vs_dwell_pct,
    
    -- Capture Rate 3: Clean Visit Pings (accuracy_m <= 30) / dwell_minutes
    SAFE_DIVIDE(COALESCE(g.total_visit_pings_clean, 0) * 100.0, s.dwell_minutes) AS capture_rate_clean_vs_dwell_pct,
    
    -- Capture Rate 4: All Visit Pings / Empirical Geolocation Span (First-to-Last Ping)
    SAFE_DIVIDE(COALESCE(g.total_visit_pings_all, 0) * 100.0, g.empirical_geo_span_min) AS capture_rate_vs_geo_span_pct,
    
    -- Spend Velocity (ILS per minute) for Bonus 3c Outlier Check
    SAFE_DIVIDE(s.total, s.dwell_minutes) AS ils_per_minute
  FROM `bqproj26.Final_Project_2026.log_sales` AS s
  LEFT JOIN daily_customer_pings AS g
    ON s.customer_id = g.device_id
   AND DATE(s.timestamp) = g.visit_date
  WHERE s.customer_id IS NOT NULL
    AND s.dwell_minutes IS NOT NULL
)

-- Final Output: Summary of Empirical App Capture Rates & Outlier Flags by Segment
SELECT
  customer_segment,
  COUNT(*) AS total_tracked_visits,
  COUNTIF(total_visit_pings_all = 0) AS visits_with_zero_geo_pings,
  
  -- Average Dwell & Ping Counts per Visit
  ROUND(AVG(dwell_minutes), 2) AS mean_dwell_min,
  ROUND(AVG(empirical_geo_span_min), 2) AS mean_geo_span_min,
  ROUND(AVG(total_visit_pings_all), 2) AS mean_total_pings_all,
  ROUND(AVG(instore_pings_all), 2) AS mean_instore_pings_all,
  ROUND(AVG(parking_pings_all), 2) AS mean_parking_pings_all,
  ROUND(AVG(total_visit_pings_clean), 2) AS mean_total_pings_clean,
  
  -- Empirical Capture Rate 1: Total Pings (incl. Parking) / dwell_minutes (Target = 40%)
  ROUND(AVG(capture_rate_all_vs_dwell_pct), 2) AS mean_capture_all_vs_dwell_pct,
  ROUND(APPROX_QUANTILES(capture_rate_all_vs_dwell_pct, 100)[OFFSET(50)], 2) AS median_capture_all_vs_dwell_pct,
  ROUND(SAFE_DIVIDE(SUM(total_visit_pings_all) * 100.0, SUM(dwell_minutes)), 2) AS weighted_capture_all_vs_dwell_pct,
  
  -- Empirical Capture Rate 2: In-Store Pings (excl. Parking) / dwell_minutes
  ROUND(AVG(capture_rate_instore_vs_dwell_pct), 2) AS mean_capture_instore_vs_dwell_pct,
  ROUND(SAFE_DIVIDE(SUM(instore_pings_all) * 100.0, SUM(dwell_minutes)), 2) AS weighted_capture_instore_vs_dwell_pct,
  
  -- Empirical Capture Rate 3: Clean Pings (accuracy_m <= 30) / dwell_minutes
  ROUND(AVG(capture_rate_clean_vs_dwell_pct), 2) AS mean_capture_clean_vs_dwell_pct,
  ROUND(SAFE_DIVIDE(SUM(total_visit_pings_clean) * 100.0, SUM(dwell_minutes)), 2) AS weighted_capture_clean_vs_dwell_pct,
  
  -- Empirical Capture Rate 4: Total Pings / Empirical Geo Span (First-to-Last Ping)
  ROUND(AVG(capture_rate_vs_geo_span_pct), 2) AS mean_capture_vs_geo_span_pct,
  
  -- SLA Compliance (% of individual visits achieving >= 40% capture rate)
  ROUND(SAFE_DIVIDE(COUNTIF(capture_rate_all_vs_dwell_pct >= 40.0) * 100.0, COUNT(*)), 2) AS pct_visits_meeting_40pct_sla_all,
  ROUND(SAFE_DIVIDE(COUNTIF(capture_rate_instore_vs_dwell_pct >= 40.0) * 100.0, COUNT(*)), 2) AS pct_visits_meeting_40pct_sla_instore,
  
  -- Bonus 3c: Additional Outliers in Dwell Time, Basket Size & Capture Rate
  COUNTIF(dwell_minutes > 120) AS outlier_dwell_gt_120m,
  COUNTIF(dwell_minutes < 10) AS outlier_dwell_lt_10m,
  COUNTIF(basket_ils > 1000) AS outlier_basket_gt_1000ils,
  COUNTIF(capture_rate_all_vs_dwell_pct > 100.0) AS anomaly_capture_gt_100pct
FROM matched_visit_performance
GROUP BY ROLLUP(customer_segment)
ORDER BY customer_segment ASC;
