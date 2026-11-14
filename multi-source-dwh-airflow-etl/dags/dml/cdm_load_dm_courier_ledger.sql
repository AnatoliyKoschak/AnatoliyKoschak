WITH settings AS (
    -- 1. Считываем дату начала последнего рассчитанного месяца из персональной настройки
    SELECT (workflow_settings->>'last_settlement_month')::DATE AS last_month_start
    FROM cdm.srv_wf_settings 
    WHERE workflow_key = 'load_courier_ledger_to_cdm'
),
courier_monthly_rates AS (
    -- 2. Рассчитываем средний рейтинг курьера за каждый закрытый месяц после last_month_start
    SELECT 
        c.id AS dds_courier_id,
        c.courier_id,
        c.courier_name,
        EXTRACT(YEAR FROM fd.order_ts)::INT AS settlement_year,
        EXTRACT(MONTH FROM fd.order_ts)::INT AS settlement_month,
        DATE_TRUNC('month', fd.order_ts)::DATE AS order_month_start,
        ROUND(AVG(fd.rate), 2) AS rate_avg
    FROM dds.fct_deliveries fd
    JOIN dds.dm_couriers c ON fd.courier_id = c.id
    JOIN dds.dm_orders o ON fd.order_id = o.id
    CROSS JOIN settings s
    WHERE o.order_status = 'CLOSED'
      -- Берём месяцы строго новее последнего рассчитанного
      AND DATE_TRUNC('month', fd.order_ts)::DATE > s.last_month_start
      -- Исключаем текущий незавершённый календарный месяц
      AND DATE_TRUNC('month', fd.order_ts)::DATE < DATE_TRUNC('month', CURRENT_DATE)::DATE
    GROUP BY 
        c.id, 
        c.courier_id, 
        c.courier_name, 
        settlement_year, 
        settlement_month, 
        order_month_start
),
order_payouts AS (
    -- 3. Вычисляем выплату за каждый заказ с учётом среднего рейтинга за месяц
    SELECT 
        cmr.courier_id,
        cmr.courier_name,
        cmr.settlement_year,
        cmr.settlement_month,
        cmr.order_month_start,
        cmr.rate_avg,
        fd.order_id,
        fd.sum AS order_sum,
        fd.tip_sum AS order_tip_sum,
        CASE 
            WHEN cmr.rate_avg < 4.0 THEN GREATEST(fd.sum * 0.05, 100.00)
            WHEN cmr.rate_avg >= 4.0 AND cmr.rate_avg < 4.5 THEN GREATEST(fd.sum * 0.07, 150.00)
            WHEN cmr.rate_avg >= 4.5 AND cmr.rate_avg < 4.9 THEN GREATEST(fd.sum * 0.08, 175.00)
            ELSE GREATEST(fd.sum * 0.10, 200.00)
        END AS courier_order_payout
    FROM dds.fct_deliveries fd
    JOIN dds.dm_orders o ON fd.order_id = o.id
    JOIN courier_monthly_rates cmr 
      ON fd.courier_id = cmr.dds_courier_id
     AND DATE_TRUNC('month', fd.order_ts)::DATE = cmr.order_month_start
    WHERE o.order_status = 'CLOSED'
),
aggregated_ledger AS (
    -- 4. Агрегируем финальные метрики витрины за месяц
    SELECT 
        courier_id,
        courier_name,
        settlement_year,
        settlement_month,
        order_month_start,
        COUNT(DISTINCT order_id)::INT AS orders_count,
        SUM(order_sum)::NUMERIC(14, 2) AS orders_total_sum,
        MAX(rate_avg)::NUMERIC(3, 2) AS rate_avg,
        ROUND(SUM(order_sum) * 0.25, 2)::NUMERIC(14, 2) AS order_processing_fee,
        ROUND(SUM(courier_order_payout), 2)::NUMERIC(14, 2) AS courier_order_sum,
        SUM(order_tip_sum)::NUMERIC(14, 2) AS courier_tips_sum,
        ROUND(SUM(courier_order_payout) + SUM(order_tip_sum) * 0.95, 2)::NUMERIC(14, 2) AS courier_reward_sum
    FROM order_payouts
    GROUP BY courier_id, courier_name, settlement_year, settlement_month, order_month_start
),
do_upsert AS (
    -- 5. Идемпотентный Upsert в витрину cdm.dm_courier_ledger
    INSERT INTO cdm.dm_courier_ledger (
        courier_id,
        courier_name,
        settlement_year,
        settlement_month,
        orders_count,
        orders_total_sum,
        rate_avg,
        order_processing_fee,
        courier_order_sum,
        courier_tips_sum,
        courier_reward_sum
    )
    SELECT 
        courier_id,
        courier_name,
        settlement_year,
        settlement_month,
        orders_count,
        orders_total_sum,
        rate_avg,
        order_processing_fee,
        courier_order_sum,
        courier_tips_sum,
        courier_reward_sum
    FROM aggregated_ledger
    ON CONFLICT (courier_id, settlement_year, settlement_month) DO UPDATE 
    SET 
        courier_name         = EXCLUDED.courier_name,
        orders_count         = EXCLUDED.orders_count,
        orders_total_sum     = EXCLUDED.orders_total_sum,
        rate_avg             = EXCLUDED.rate_avg,
        order_processing_fee = EXCLUDED.order_processing_fee,
        courier_order_sum    = EXCLUDED.courier_order_sum,
        courier_tips_sum     = EXCLUDED.courier_tips_sum,
        courier_reward_sum   = EXCLUDED.courier_reward_sum
    RETURNING settlement_year
)
-- 6. Сдвигаем метку прогресса в персональной настройке cdm.srv_wf_settings
UPDATE cdm.srv_wf_settings
SET workflow_settings = json_build_object(
    'last_settlement_month', 
    (SELECT COALESCE(MAX(order_month_start), (SELECT last_month_start FROM settings)) FROM aggregated_ledger)
)
WHERE workflow_key = 'load_courier_ledger_to_cdm';
