/* ==============================================================================
   File: 06_part3_business_recommendations_track_b.sql
   Project: Penlink Final Project - Shefa Issachar (Yavne Branch)
   Part 3 - Option 3B (VP Avichai Gratzian):
     * Query 3B_2: Promotions & Discount Timing Matrix (Traffic, Basket & App Adoption)
     * Query 3B_3: HR Cashier Shift Staffing & Self-Checkout Capacity Model
     * Query 3B_4: Payroll Audit - Zero-Activity Dates (Holidays/Saturdays) & Surge Dates
   ============================================================================== */

-- ==============================================================================
-- Query 3B_2 & 3B_3 Unified: Hourly & Shift-Level Traffic, Sales, Promotions 
--                            and HR Cashier Capacity Model by Day Regime
-- ==============================================================================
WITH daily_hourly_geo AS (
  -- Step 1: Aggregate hourly store presence from `geolocation` per calendar date
  SELECT
    DATE(timestamp) AS activity_date,
    EXTRACT(DAYOFWEEK FROM DATE(timestamp)) AS day_num, -- 1=Sun .. 6=Fri
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,
    
    -- Customer segments present in the store during this hour
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id END) AS total_app_visitors,
    COUNT(DISTINCT CASE WHEN role = 'repeat_customer' THEN device_id END) AS repeat_visitors,
    COUNT(DISTINCT CASE WHEN role = 'one_time_customer' THEN device_id END) AS one_time_visitors,
    COUNT(DISTINCT CASE WHEN role = 'not_paying' THEN device_id END) AS non_paying_visitors,
    
    -- Staff & Cashiers on duty during this hour
    COUNT(DISTINCT CASE WHEN role = 'cashier' THEN device_id END) AS actual_cashiers_on_duty,
    COUNT(DISTINCT CASE WHEN role NOT IN ('repeat_customer', 'one_time_customer', 'not_paying', 'delivery_guy') THEN device_id END) AS total_staff_on_duty,
    
    -- Customers actively queuing/passing through CASH_REGISTERS polygon
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer') AND area = 'CASH_REGISTERS' THEN device_id END) AS customers_at_registers_geo
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY activity_date, day_num, hour_of_day
),

daily_hourly_sales AS (
  -- Step 2: Aggregate hourly checkout transactions & revenue from `log_sales` per calendar date
  SELECT
    DATE(timestamp) AS sale_date,
    EXTRACT(DAYOFWEEK FROM DATE(timestamp)) AS day_num,
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,
    COUNT(DISTINCT sale_id) AS total_tx,
    COUNTIF(customer_id IS NOT NULL) AS app_tx,
    COUNTIF(customer_id IS NULL) AS no_phone_tx,
    COUNTIF(total < 200) AS small_basket_tx_lt200,
    ROUND(SUM(total), 2) AS hourly_revenue_ils,
    ROUND(AVG(total), 2) AS avg_basket_ils,
    ROUND(AVG(dwell_minutes), 1) AS avg_dwell_min
  FROM `bqproj26.Final_Project_2026.log_sales`
  GROUP BY sale_date, day_num, hour_of_day
),

combined_daily_hourly AS (
  -- Step 3: Full join of daily-hourly Geolocation presence and Checkout Sales
  SELECT
    COALESCE(g.activity_date, s.sale_date) AS calendar_date,
    COALESCE(g.day_num, s.day_num) AS day_num,
    CASE
      WHEN COALESCE(g.day_num, s.day_num) BETWEEN 1 AND 4 THEN '1_Sun_to_Wed (א-ד שגרה)'
      WHEN COALESCE(g.day_num, s.day_num) = 5 THEN '2_Thursday (ה שיא חמישי)'
      WHEN COALESCE(g.day_num, s.day_num) = 6 THEN '3_Friday (ו שיא שישי)'
      ELSE '4_Saturday'
    END AS day_regime,
    COALESCE(g.hour_of_day, s.hour_of_day) AS hour_of_day,
    CASE
      WHEN COALESCE(g.hour_of_day, s.hour_of_day) BETWEEN 7 AND 14 THEN 'Shift_1_Morning (07:30-15:00)'
      WHEN COALESCE(g.hour_of_day, s.hour_of_day) BETWEEN 15 AND 22 THEN 'Shift_2_Evening (15:00-22:00)'
      ELSE 'Off_Hours_Logistics (05:00-06:59 / 23:00)'
    END AS store_shift,
    
    COALESCE(g.total_app_visitors, 0) AS total_app_visitors,
    COALESCE(g.repeat_visitors, 0) AS repeat_visitors,
    COALESCE(g.one_time_visitors, 0) AS one_time_visitors,
    COALESCE(g.non_paying_visitors, 0) AS non_paying_visitors,
    COALESCE(g.actual_cashiers_on_duty, 0) AS actual_cashiers_on_duty,
    COALESCE(g.total_staff_on_duty, 0) AS total_staff_on_duty,
    
    COALESCE(s.total_tx, 0) AS total_tx,
    COALESCE(s.app_tx, 0) AS app_tx,
    COALESCE(s.no_phone_tx, 0) AS no_phone_tx,
    COALESCE(s.small_basket_tx_lt200, 0) AS small_basket_tx_lt200,
    COALESCE(s.hourly_revenue_ils, 0.0) AS hourly_revenue_ils,
    s.avg_basket_ils,
    s.avg_dwell_min
  FROM daily_hourly_geo AS g
  FULL OUTER JOIN daily_hourly_sales AS s
    ON g.activity_date = s.sale_date
   AND g.hour_of_day = s.hour_of_day
  WHERE COALESCE(g.hour_of_day, s.hour_of_day) BETWEEN 7 AND 22
)

-- Final Output for Queries 3B_2 (Promotions) & 3B_3 (HR Cashier Staffing):
SELECT
  day_regime,
  store_shift,
  hour_of_day,
  COUNT(DISTINCT calendar_date) AS active_days_sampled,
  
  -- 1. Visitor Traffic & Segment Mix (Geolocation)
  ROUND(AVG(total_app_visitors), 1) AS mean_app_visitors,
  ROUND(AVG(repeat_visitors), 1) AS mean_repeat_visitors,
  ROUND(AVG(one_time_visitors), 1) AS mean_onetime_visitors,
  ROUND(AVG(non_paying_visitors), 1) AS mean_nonpaying_visitors,
  
  -- 2. Checkout Transactions & Revenue Mix (`log_sales`)
  ROUND(AVG(total_tx), 1) AS mean_tx_per_hour,
  MAX(total_tx) AS max_tx_per_hour,
  ROUND(AVG(no_phone_tx), 1) AS mean_no_phone_tx,
  ROUND(SAFE_DIVIDE(SUM(no_phone_tx) * 100.0, NULLIF(SUM(total_tx), 0)), 1) AS pct_no_phone_tx,
  ROUND(SAFE_DIVIDE(SUM(small_basket_tx_lt200) * 100.0, NULLIF(SUM(total_tx), 0)), 1) AS pct_small_baskets_lt200,
  ROUND(AVG(hourly_revenue_ils), 0) AS mean_hourly_rev_ils,
  ROUND(AVG(avg_basket_ils), 2) AS mean_basket_ils,
  
  -- 3. HR Cashier Staffing & Queuing Capacity Model (Benchmark = 12 tx/hour per human cashier)
  ROUND(AVG(actual_cashiers_on_duty), 2) AS mean_actual_cashiers,
  MAX(actual_cashiers_on_duty) AS max_actual_cashiers,
  ROUND(SAFE_DIVIDE(AVG(total_tx), NULLIF(AVG(actual_cashiers_on_duty), 0)), 1) AS empirical_tx_per_cashier_hr,
  
  -- Optimal Human Cashiers Needed (Assuming 12 tx/hr capacity for large baskets ~480 ILS)
  CAST(CEIL(SAFE_DIVIDE(AVG(total_tx), 12.0)) AS INT64) AS optimal_cashiers_avg_load,
  CAST(CEIL(SAFE_DIVIDE(MAX(total_tx), 12.0)) AS INT64) AS optimal_cashiers_peak_load,
  
  -- Staffing Gap: Positive = Overstaffed (Idle Cashiers), Negative = Understaffed (Queue Bottleneck)
  ROUND(AVG(actual_cashiers_on_duty) - CEIL(SAFE_DIVIDE(AVG(total_tx), 12.0)), 2) AS cashier_surplus_or_deficit
FROM combined_daily_hourly
GROUP BY
  day_regime,
  store_shift,
  hour_of_day
ORDER BY
  day_regime ASC,
  hour_of_day ASC;




-- ==============================================================================
-- Query 3B_4: Payroll & Calendar Audit - Exact Zero-Activity Dates (4a) 
--             and Extreme Customer Surge Dates (4b)
-- ==============================================================================
WITH calendar_bounds AS (
  SELECT
    MIN(DATE(timestamp)) AS start_date,
    MAX(DATE(timestamp)) AS end_date
  FROM `bqproj26.Final_Project_2026.geolocation`
),

full_calendar AS (
  SELECT
    cal_date,
    EXTRACT(DAYOFWEEK FROM cal_date) AS day_num, -- 1=Sun .. 7=Sat
    FORMAT_DATE('%A', cal_date) AS day_name
  FROM calendar_bounds,
  UNNEST(GENERATE_DATE_ARRAY(start_date, end_date, INTERVAL 1 DAY)) AS cal_date
),

daily_geo_summary AS (
  SELECT
    DATE(timestamp) AS activity_date,
    COUNT(*) AS total_pings,
    COUNT(DISTINCT CASE WHEN role IN ('repeat_customer', 'one_time_customer', 'not_paying') THEN device_id END) AS unique_customers_geo,
    COUNT(DISTINCT CASE WHEN role NOT IN ('repeat_customer', 'one_time_customer', 'not_paying', 'delivery_guy') THEN device_id END) AS unique_staff_geo
  FROM `bqproj26.Final_Project_2026.geolocation`
  GROUP BY DATE(timestamp)
),

daily_sales_summary AS (
  SELECT
    DATE(timestamp) AS sale_date,
    COUNT(DISTINCT sale_id) AS total_transactions,
    ROUND(SUM(total), 2) AS daily_revenue_ils,
    ROUND(AVG(total), 2) AS avg_basket_ils
  FROM `bqproj26.Final_Project_2026.log_sales`
  GROUP BY DATE(timestamp)
),

daily_merged AS (
  SELECT
    c.cal_date,
    c.day_num,
    c.day_name,
    COALESCE(g.total_pings, 0) AS total_pings,
    COALESCE(g.unique_customers_geo, 0) AS unique_customers_geo,
    COALESCE(g.unique_staff_geo, 0) AS unique_staff_geo,
    COALESCE(s.total_transactions, 0) AS total_transactions,
    COALESCE(s.daily_revenue_ils, 0.0) AS daily_revenue_ils,
    s.avg_basket_ils
  FROM full_calendar AS c
  LEFT JOIN daily_geo_summary AS g ON c.cal_date = g.activity_date
  LEFT JOIN daily_sales_summary AS s ON c.cal_date = s.sale_date
),

daily_with_stats AS (
  SELECT
    *,
    -- Compare each active day against the average of the SAME Day of Week (e.g., Tuesday vs avg Tuesday)
    ROUND(AVG( CASE WHEN total_pings > 0 THEN unique_customers_geo END ) OVER (PARTITION BY day_num), 1) AS dow_mean_customers,
    ROUND(STDDEV( CASE WHEN total_pings > 0 THEN unique_customers_geo END ) OVER (PARTITION BY day_num), 1) AS dow_sd_customers,
    ROUND(
      SAFE_DIVIDE(
        unique_customers_geo - AVG(CASE WHEN total_pings > 0 THEN unique_customers_geo END) OVER (PARTITION BY day_num),
        STDDEV(CASE WHEN total_pings > 0 THEN unique_customers_geo END) OVER (PARTITION BY day_num)
      ),
      2
    ) AS dow_z_score_customers,
    
    -- Overall Z-Score across all 151 active operating days
    ROUND(
      SAFE_DIVIDE(
        unique_customers_geo - AVG(CASE WHEN total_pings > 0 THEN unique_customers_geo END) OVER (),
        STDDEV(CASE WHEN total_pings > 0 THEN unique_customers_geo END) OVER ()
      ),
      2
    ) AS overall_z_score_customers,
    
    RANK() OVER (ORDER BY unique_customers_geo DESC, total_transactions DESC) AS customer_volume_rank
  FROM daily_merged
)

SELECT
  cal_date,
  day_name,
  unique_customers_geo,
  dow_mean_customers,
  dow_z_score_customers,
  overall_z_score_customers,
  unique_staff_geo,
  total_transactions,
  daily_revenue_ils,
  avg_basket_ils,
  total_pings,
  CASE
    WHEN total_pings = 0 AND total_transactions = 0 AND day_num = 7 
      THEN '4A_CLOSED_REGULAR_SATURDAY (שבת - סגור בשגרה)'
    WHEN total_pings = 0 AND total_transactions = 0 AND day_num != 7 
      THEN '4A_CLOSED_WEEKDAY_HOLIDAY (חג באמצע השבוע - 0 פעילות!)'
    WHEN dow_z_score_customers >= 2.0 OR customer_volume_rank <= 10 
      THEN '4B_EXTREME_SURGE_DAY (פעילות יתרה חריגה / ערב חג או שיא)'
    WHEN dow_z_score_customers <= -2.0 AND total_pings > 0
      THEN '4C_ABNORMAL_LOW_ACTIVITY_DAY (פעילות נמוכה חריגה)'
    ELSE 'NORMAL_OPERATING_DAY'
  END AS payroll_audit_category
FROM daily_with_stats
WHERE (total_pings = 0 AND total_transactions = 0 AND day_num != 7) -- All Weekday Holidays with 0 activity
   OR (total_pings = 0 AND total_transactions = 0 AND cal_date <= '2025-06-15') -- Sample of Saturdays (plus count in summary)
   OR dow_z_score_customers >= 1.8
   OR customer_volume_rank <= 15
   OR (dow_z_score_customers <= -1.8 AND total_pings > 0)
ORDER BY
  CASE
    WHEN total_pings = 0 AND day_num != 7 THEN 1
    WHEN total_pings = 0 AND day_num = 7 THEN 2
    WHEN dow_z_score_customers >= 1.8 OR customer_volume_rank <= 15 THEN 3
    ELSE 4
  END ASC,
  cal_date ASC;
