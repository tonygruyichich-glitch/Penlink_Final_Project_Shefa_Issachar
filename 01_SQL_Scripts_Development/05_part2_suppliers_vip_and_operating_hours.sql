/* ==============================================================================
   File: 05_part2_suppliers_vip_and_operating_hours.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Part 2 - Tasks 4, 5 & 6: 
     * Task 4 (a, b Bonus, c): Supplier Identification (without `role`) & Missed Delivery Dates
     * Task 5 (a, b): Top 5 VIP Customers by Visit Frequency & Cumulative Spend
     * Task 6: Real Store Operating Hours (Day of Week x Hour of Day x Customer Traffic)
   ============================================================================== */

-- ==============================================================================
-- Query 4A & 4B (Bonus): Identify Supplier Devices WITH and WITHOUT `role` Column
-- ==============================================================================
WITH device_behavior_summary AS (
  SELECT
    g.device_id,
    ANY_VALUE(g.role) AS actual_role,
    COUNT(*) AS total_pings,
    COUNT(DISTINCT DATE(g.timestamp)) AS active_days,
    MIN(EXTRACT(HOUR FROM g.timestamp)) AS earliest_hour,
    MAX(EXTRACT(HOUR FROM g.timestamp)) AS latest_hour,
    
    -- Spatial & Temporal Supplier Indicators (Ignoring `role` column!)
    COUNTIF(g.area = 'WAREHOUSE') AS warehouse_pings,
    COUNTIF(EXTRACT(DAYOFWEEK FROM g.timestamp) IN (2, 5)) AS mon_thu_pings,
    COUNTIF(EXTRACT(HOUR FROM g.timestamp) BETWEEN 5 AND 7) AS early_morning_05_07_pings,
    
    -- Check transactions in `log_sales`
    COUNT(DISTINCT s.sale_id) AS total_purchases
  FROM `bqproj26.Final_Project_2026.geolocation` AS g
  LEFT JOIN `bqproj26.Final_Project_2026.log_sales` AS s
    ON g.device_id = s.customer_id
  GROUP BY g.device_id
)

SELECT
  device_id,
  actual_role,
  -- Bonus 4b Logic: Classify as `delivery_guy` purely via spatiotemporal rules
  CASE
    WHEN total_purchases = 0
     AND warehouse_pings > 0
     AND mon_thu_pings = total_pings
     AND early_morning_05_07_pings = total_pings
    THEN 'delivery_guy'
    ELSE 'other'
  END AS inferred_supplier_role,
  total_pings,
  active_days,
  ROUND(SAFE_DIVIDE(total_pings, active_days), 2) AS avg_pings_per_delivery,
  earliest_hour,
  latest_hour,
  warehouse_pings,
  mon_thu_pings,
  early_morning_05_07_pings
FROM device_behavior_summary
WHERE actual_role = 'delivery_guy'
   OR (total_purchases = 0 AND warehouse_pings > 0)
ORDER BY device_id ASC;


-- ==============================================================================
-- Query 4C: Detect Exact Scheduled Dates (Mondays & Thursdays) with MISSED Deliveries
-- ==============================================================================
WITH date_bounds AS (
  SELECT
    MIN(DATE(timestamp)) AS min_date,
    MAX(DATE(timestamp)) AS max_date
  FROM `bqproj26.Final_Project_2026.geolocation`
),

scheduled_delivery_calendar AS (
  -- Generate all Mondays (DAYOFWEEK = 2) and Thursdays (DAYOFWEEK = 5) in the 6-month period
  SELECT
    calendar_date,
    EXTRACT(DAYOFWEEK FROM calendar_date) AS day_of_week_num,
    FORMAT_DATE('%A', calendar_date) AS day_name
  FROM date_bounds,
  UNNEST(GENERATE_DATE_ARRAY(min_date, max_date, INTERVAL 1 DAY)) AS calendar_date
  WHERE EXTRACT(DAYOFWEEK FROM calendar_date) IN (2, 5)
),

daily_branch_and_supplier_activity AS (
  SELECT
    DATE(timestamp) AS activity_date,
    -- Total store activity (to distinguish closed holidays from open workdays)
    COUNT(*) AS total_branch_pings,
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id END) AS active_customers,
    COUNT(DISTINCT CASE WHEN role NOT IN ('repeat_customer', 'one_time_customer', 'not_paying', 'delivery_guy') THEN device_id END) AS active_staff,
    
    -- Supplier activity (using behavioral rule: WAREHOUSE pings on Mon/Thu early morning)
    COUNT(DISTINCT CASE WHEN area = 'WAREHOUSE' THEN device_id END) AS unique_suppliers_arrived,
    COUNTIF(area = 'WAREHOUSE') AS supplier_warehouse_pings,
    MIN(CASE WHEN area = 'WAREHOUSE' THEN TIME(timestamp) END) AS first_supplier_ping_time,
    MAX(CASE WHEN area = 'WAREHOUSE' THEN TIME(timestamp) END) AS last_supplier_ping_time
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY DATE(timestamp)
)

SELECT
  c.calendar_date,
  c.day_name,
  COALESCE(a.unique_suppliers_arrived, 0) AS suppliers_arrived,
  COALESCE(a.supplier_warehouse_pings, 0) AS supplier_pings,
  a.first_supplier_ping_time,
  a.last_supplier_ping_time,
  COALESCE(a.active_staff, 0) AS branch_staff_present,
  COALESCE(a.active_customers, 0) AS branch_customers_present,
  COALESCE(a.total_branch_pings, 0) AS total_branch_pings,
  
  -- Diagnostic Status of the Scheduled Delivery Day
  CASE
    WHEN COALESCE(a.unique_suppliers_arrived, 0) = 0 AND COALESCE(a.total_branch_pings, 0) > 0 
      THEN 'MISSED_DELIVERY_STORE_OPEN (ספק לא הגיע למרות שהסניף פתוח!)'
    WHEN COALESCE(a.unique_suppliers_arrived, 0) = 0 AND COALESCE(a.total_branch_pings, 0) = 0 
      THEN 'NO_DELIVERY_STORE_CLOSED_HOLIDAY (הסניף סגור לחלוטין - חג)'
    ELSE 'NORMAL_DELIVERY_ARRIVED (אספקה תקינה)'
  END AS delivery_status
FROM scheduled_delivery_calendar AS c
LEFT JOIN daily_branch_and_supplier_activity AS a
  ON c.calendar_date = a.activity_date
WHERE COALESCE(a.unique_suppliers_arrived, 0) = 0  -- Filter directly to missed delivery dates!
ORDER BY c.calendar_date ASC;


-- ==============================================================================
-- Query 5A & 5B: Top 5 Loyal Customers (Visit Frequency) & Top 5 Spenders (Cumulative Spend)
-- ==============================================================================
WITH customer_vip_metrics AS (
  SELECT
    s.customer_id,
    ANY_VALUE(g.role) AS customer_segment,
    COUNT(DISTINCT s.sale_id) AS total_purchases,
    COUNT(DISTINCT DATE(s.timestamp)) AS unique_purchase_days,
    g.active_geo_days,
    g.total_geo_pings,
    ROUND(SUM(s.total), 2) AS cumulative_spend_ils,
    ROUND(AVG(s.total), 2) AS avg_basket_ils,
    ROUND(AVG(s.dwell_minutes), 1) AS avg_dwell_minutes,
    MIN(DATE(s.timestamp)) AS first_visit_date,
    MAX(DATE(s.timestamp)) AS last_visit_date
  FROM `bqproj26.Final_Project_2026.log_sales` AS s
  LEFT JOIN (
    SELECT
      device_id,
      ANY_VALUE(role) AS role,
      COUNT(DISTINCT DATE(timestamp)) AS active_geo_days,
      COUNT(*) AS total_geo_pings
    FROM `bqproj26.Final_Project_2026.geolocation`
    GROUP BY device_id
  ) AS g
    ON s.customer_id = g.device_id
  WHERE s.customer_id IS NOT NULL
  GROUP BY
    s.customer_id,
    g.active_geo_days,
    g.total_geo_pings
),

ranked_vips AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY total_purchases DESC, active_geo_days DESC, cumulative_spend_ils DESC) AS rank_by_frequency,
    DENSE_RANK() OVER (ORDER BY total_purchases DESC) AS dense_rank_frequency,
    ROW_NUMBER() OVER (ORDER BY cumulative_spend_ils DESC, total_purchases DESC) AS rank_by_spend
  FROM customer_vip_metrics
)

SELECT
  CASE
    WHEN rank_by_frequency <= 5 AND rank_by_spend <= 5 THEN 'BOTH_TOP5_FREQ_AND_SPEND'
    WHEN rank_by_frequency <= 5 THEN '5A_TOP_5_BY_FREQUENCY (Titinsky Style)'
    WHEN rank_by_spend <= 5 THEN '5B_TOP_5_BY_CUMULATIVE_SPEND'
  END AS vip_award_category,
  rank_by_frequency,
  dense_rank_frequency,
  rank_by_spend,
  customer_id,
  customer_segment,
  total_purchases,
  unique_purchase_days,
  active_geo_days,
  cumulative_spend_ils,
  avg_basket_ils,
  avg_dwell_minutes,
  first_visit_date,
  last_visit_date
FROM ranked_vips
WHERE rank_by_frequency <= 5
   OR rank_by_spend <= 5
ORDER BY
  vip_award_category ASC,
  rank_by_frequency ASC,
  rank_by_spend ASC;




-- ==============================================================================
-- Query 6: Real vs. Declared Store Operating Hours (Day of Week x Hour x Customers)
-- ==============================================================================
WITH daily_hourly_presence AS (
  SELECT
    DATE(timestamp) AS visit_date,
    EXTRACT(DAYOFWEEK FROM DATE(timestamp)) AS day_of_week_num, -- 1=Sun .. 6=Fri
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,
    -- Count all tracked customer devices present in the store (including >30m accuracy)
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id END) AS customer_devices_all,
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') AND accuracy_m <= 30 THEN device_id END) AS customer_devices_clean,
    COUNT(DISTINCT CASE WHEN role NOT IN ('repeat_customer', 'one_time_customer', 'not_paying', 'delivery_guy') THEN device_id END) AS staff_devices
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY visit_date, day_of_week_num, hour_of_day
)

SELECT
  day_of_week_num,
  CASE day_of_week_num
    WHEN 1 THEN '1_Sunday'
    WHEN 2 THEN '2_Monday'
    WHEN 3 THEN '3_Tuesday'
    WHEN 4 THEN '4_Wednesday'
    WHEN 5 THEN '5_Thursday'
    WHEN 6 THEN '6_Friday'
  END AS day_name,
  hour_of_day,
  COUNT(DISTINCT visit_date) AS days_observed,
  ROUND(AVG(customer_devices_all), 2) AS mean_customers_all,
  ROUND(AVG(customer_devices_clean), 2) AS mean_customers_clean_le30m,
  APPROX_QUANTILES(customer_devices_all, 4)[OFFSET(2)] AS median_customers_all,
  MAX(customer_devices_all) AS max_customers_all,
  ROUND(AVG(staff_devices), 2) AS mean_staff_devices,
  CASE
    WHEN AVG(customer_devices_all) >= 80 THEN 'PEAK_CONGESTION_HOUR'
    WHEN AVG(customer_devices_all) >= 15 THEN 'ACTIVE_SHOPPING_HOUR'
    WHEN AVG(customer_devices_all) > 0 THEN 'MARGINAL_EXIT_TAIL_HOUR'
    ELSE 'DEAD_HOUR_ZERO_CUSTOMERS (פתוח לצוות בלבד - 0 לקוחות)'
  END AS operational_hour_status
FROM daily_hourly_presence
GROUP BY day_of_week_num, day_name, hour_of_day
ORDER BY day_of_week_num ASC, hour_of_day ASC;
