/* ==============================================================================
   File: sql/02_segmentation_customers_staff.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Part 2 - Tasks 1, 2 & Bonus: Unified Behavioral Segmentation & Reverse Engineering
            of All 11 Roles (4 Customer Segments + 7 Staff/Supplier Roles) WITHOUT `role`
   ============================================================================== */

WITH customer_sales_agg AS (
  -- Step 1: Aggregate transaction metrics per identified customer from `log_sales`
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

device_geo_agg AS (
  -- Step 2: Build Spatiotemporal & Signal Fingerprint per `device_id` from `geolocation`
  SELECT
    device_id,
    ANY_VALUE(role) AS actual_role,
    COUNT(*) AS total_pings,
    COUNT(DISTINCT DATE(timestamp)) AS active_geo_days,
    SAFE_DIVIDE(COUNT(*), COUNT(DISTINCT DATE(timestamp))) AS pings_per_active_day,
    ROUND(AVG(accuracy_m), 2) AS avg_accuracy_m,
    ROUND(SAFE_DIVIDE(COUNTIF(accuracy_m > 30) * 100.0, COUNT(*)), 1) AS pct_outlier_accuracy,
    
    -- Raw Pings per Store Zone
    COUNTIF(area = 'SUPERMARKET') AS supermarket_pings,
    COUNTIF(area = 'PARKING') AS parking_pings,
    COUNTIF(area = 'CASH_REGISTERS') AS cash_register_pings,
    COUNTIF(area = 'BUTCHERY') AS butchery_pings,
    COUNTIF(area = 'WAREHOUSE') AS warehouse_pings,
    COUNTIF(area = 'HEAD_OFFICE') AS head_office_pings,
    
    -- Temporal Fingerprint (Early Morning 05:00-06:59 Pings)
    COUNTIF(EXTRACT(HOUR FROM timestamp) IN (5, 6)) AS early_morning_pings
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY device_id
),

classified_tracked_entities AS (
  -- Step 3: Apply the 10-Way Behavioral Decision Tree to all tracked devices (Ignoring `role`!)
  SELECT
    g.device_id AS entity_id,
    g.actual_role,
    
    CASE
      -- A. Paying App Customers (Separated by Purchase Frequency)
      WHEN COALESCE(s.total_purchases, 0) >= 10 THEN 'repeat_customer'
      WHEN COALESCE(s.total_purchases, 0) BETWEEN 1 AND 9 THEN 'one_time_customer'
      
      -- B. Specialized Zone Staff & Suppliers (0 Purchases + Exclusive Zone Footprint)
      WHEN g.head_office_pings > 0 THEN 'manager'
      WHEN g.butchery_pings > 0 THEN 'butcher'
      WHEN g.warehouse_pings > 0 THEN 'delivery_guy'
      WHEN g.cash_register_pings > g.supermarket_pings 
       AND g.cash_register_pings > g.parking_pings THEN 'cashier'
      WHEN g.parking_pings > g.supermarket_pings 
       AND g.parking_pings > g.cash_register_pings THEN 'security_guy'
       
      -- C. Sales Floor Workers vs. Non-Paying Visitors (Separated by Daily Ping Intensity & Tenure)
      WHEN g.pings_per_active_day >= 100 AND g.active_geo_days >= 100 THEN 'senior_general_worker'
      WHEN g.pings_per_active_day >= 100 AND g.active_geo_days < 100 THEN 'general_worker'
      WHEN g.pings_per_active_day < 100 AND g.supermarket_pings > 0 THEN 'not_paying'
      
      ELSE 'UNCLASSIFIED'
    END AS inferred_role,
    
    -- Group Category (Customer vs. Staff/Supplier)
    CASE
      WHEN COALESCE(s.total_purchases, 0) > 0 
        OR (g.pings_per_active_day < 100 AND g.supermarket_pings > 0 AND g.warehouse_pings = 0 AND g.head_office_pings = 0 AND g.butchery_pings = 0)
      THEN '1_Customer_Segment'
      ELSE '2_Staff_or_Supplier'
    END AS entity_group,
    
    g.active_geo_days,
    g.total_pings,
    g.pings_per_active_day,
    g.avg_accuracy_m,
    g.pct_outlier_accuracy,
    g.supermarket_pings,
    g.parking_pings,
    g.cash_register_pings,
    g.butchery_pings,
    g.warehouse_pings,
    g.head_office_pings,
    g.early_morning_pings,
    COALESCE(s.total_purchases, 0) AS total_purchases,
    COALESCE(s.total_spent_ils, 0.0) AS total_spent_ils,
    s.avg_basket_ils,
    s.avg_dwell_minutes
  FROM device_geo_agg AS g
  LEFT JOIN customer_sales_agg AS s
    ON g.device_id = s.customer_id
),

anonymous_no_phone_sales AS (
  -- Step 4: Append the 11th Segment (`no_phone` anonymous transactions from `log_sales`)
  SELECT
    CONCAT('NO_PHONE_TX_', CAST(sale_id AS STRING)) AS entity_id,
    'no_phone' AS actual_role,
    'no_phone' AS inferred_role,
    '1_Customer_Segment' AS entity_group,
    0 AS active_geo_days,
    0 AS total_pings,
    0.0 AS pings_per_active_day,
    NULL AS avg_accuracy_m,
    NULL AS pct_outlier_accuracy,
    0 AS supermarket_pings,
    0 AS parking_pings,
    0 AS cash_register_pings,
    0 AS butchery_pings,
    0 AS warehouse_pings,
    0 AS head_office_pings,
    0 AS early_morning_pings,
    1 AS total_purchases,
    ROUND(total, 2) AS total_spent_ils,
    ROUND(total, 2) AS avg_basket_ils,
    dwell_minutes AS avg_dwell_minutes
  FROM `bqproj26.Final_Project_2026.log_sales`
  WHERE customer_id IS NULL
),

all_11_segments_unified AS (
  SELECT * FROM classified_tracked_entities
  UNION ALL
  SELECT * FROM anonymous_no_phone_sales
)

-- Final Output: Complete 11-Role Classification, Spatiotemporal Profile & Validation Matrix
SELECT
  entity_group,
  inferred_role,
  actual_role AS ground_truth_role,
  COUNT(*) AS unique_entities_or_anon_tx,
  
  -- Reverse Engineering Validation (% Exact Match with Ground Truth `role`)
  ROUND(SAFE_DIVIDE(COUNTIF(inferred_role = actual_role) * 100.0, COUNT(*)), 2) AS accuracy_match_pct,
  
  -- Activity & Signal Metrics
  ROUND(AVG(NULLIF(active_geo_days, 0)), 1) AS mean_active_days,
  ROUND(AVG(NULLIF(pings_per_active_day, 0)), 1) AS mean_pings_per_day,
  SUM(total_pings) AS total_geo_pings,
  ROUND(AVG(avg_accuracy_m), 2) AS mean_accuracy_m,
  ROUND(AVG(pct_outlier_accuracy), 1) AS mean_pct_accuracy_gt_30m,
  
  -- Spatial Footprint Breakdown (% of Role's Pings in Each Area)
  ROUND(SAFE_DIVIDE(SUM(supermarket_pings) * 100.0, NULLIF(SUM(total_pings), 0)), 1) AS pct_supermarket,
  ROUND(SAFE_DIVIDE(SUM(parking_pings) * 100.0, NULLIF(SUM(total_pings), 0)), 1) AS pct_parking,
  ROUND(SAFE_DIVIDE(SUM(cash_register_pings) * 100.0, NULLIF(SUM(total_pings), 0)), 1) AS pct_cash_reg,
  ROUND(SAFE_DIVIDE(SUM(butchery_pings) * 100.0, NULLIF(SUM(total_pings), 0)), 1) AS pct_butchery,
  ROUND(SAFE_DIVIDE(SUM(warehouse_pings) * 100.0, NULLIF(SUM(total_pings), 0)), 1) AS pct_warehouse,
  ROUND(SAFE_DIVIDE(SUM(head_office_pings) * 100.0, NULLIF(SUM(total_pings), 0)), 1) AS pct_head_office,
  
  -- Commercial Metrics (`log_sales`)
  ROUND(AVG(total_purchases), 2) AS mean_purchases_per_entity,
  SUM(total_purchases) AS total_transactions,
  ROUND(SUM(total_spent_ils), 2) AS total_revenue_ils,
  ROUND(AVG(NULLIF(avg_basket_ils, 0)), 2) AS mean_basket_ils,
  ROUND(AVG(avg_dwell_minutes), 1) AS mean_dwell_min
FROM all_11_segments_unified
GROUP BY
  entity_group,
  inferred_role,
  ground_truth_role
ORDER BY
  entity_group ASC,
  total_revenue_ils DESC,
  total_geo_pings DESC;
