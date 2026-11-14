WITH settings AS (
    -- 1. Считываем дату последнего успешного расчета витрины из метаданных CDM
    SELECT (workflow_settings->>'last_settlement_date')::DATE AS last_date
    FROM cdm.srv_wf_settings 
    WHERE workflow_key = 'load_dds_to_cdm'
),
order_aggr AS (
    -- 2. Агрегируем метрики закрытых заказов из DDS за дни после сохраненной метки
    SELECT 
        o.id AS order_id,
        o.restaurant_id AS dds_restaurant_id,
        t.date AS settlement_date,
        SUM(fps.total_sum) AS order_total_sum,
        SUM(fps.bonus_payment) AS order_bonus_payment,
        SUM(fps.bonus_grant) AS order_bonus_grant
    FROM dds.dm_orders o
    JOIN dds.dm_timestamps t ON o.timestamp_id = t.id
    JOIN dds.fct_product_sales fps ON o.id = fps.order_id
    CROSS JOIN settings
    WHERE o.order_status = 'CLOSED'
      AND t.date > settings.last_date
    GROUP BY o.id, o.restaurant_id, t.date
),
restaurant_aggr AS (
    -- 3. Группируем до уровня бизнес-ключа ресторана и даты отчета
    SELECT 
        r.restaurant_id, 
        r.restaurant_name,
        oa.settlement_date,
        COUNT(DISTINCT oa.order_id)::INTEGER AS orders_count,
        SUM(oa.order_total_sum) AS orders_total_sum,
        SUM(oa.order_bonus_payment) AS orders_bonus_payment_sum,
        SUM(oa.order_bonus_grant) AS orders_bonus_granted_sum,
        -- Комиссия агрегатора (25% от общей суммы заказов)
        ROUND(SUM(oa.order_total_sum) * 0.25, 2) AS order_processing_fee,
        -- Итоговая выплата ресторану
        ROUND(SUM(oa.order_total_sum) - (SUM(oa.order_total_sum) * 0.25) - SUM(oa.order_bonus_payment), 2) AS restaurant_reward_sum
    FROM order_aggr oa
    -- Получаем бизнес-ключ и актуальное имя ресторана по его суррогатному ID из заказа
    JOIN dds.dm_restaurants r ON oa.dds_restaurant_id = r.id
    GROUP BY r.restaurant_id, r.restaurant_name, oa.settlement_date
),
do_upsert AS (
    -- 4. Выполняем идемпотентный Upsert в финальную витрину
    INSERT INTO cdm.dm_settlement_report (
        restaurant_id, 
        restaurant_name, 
        settlement_date, 
        orders_count, 
        orders_total_sum, 
        orders_bonus_payment_sum, 
        orders_bonus_granted_sum, 
        order_processing_fee, 
        restaurant_reward_sum
    )
    SELECT 
        restaurant_id, 
        restaurant_name, 
        settlement_date, 
        orders_count, 
        orders_total_sum, 
        orders_bonus_payment_sum, 
        orders_bonus_granted_sum, 
        order_processing_fee, 
        restaurant_reward_sum
    FROM restaurant_aggr
    ON CONFLICT (restaurant_id, settlement_date) DO UPDATE 
    SET 
        restaurant_name          = EXCLUDED.restaurant_name,
        orders_count             = EXCLUDED.orders_count,
        orders_total_sum         = EXCLUDED.orders_total_sum,
        orders_bonus_payment_sum = EXCLUDED.orders_bonus_payment_sum,
        orders_bonus_granted_sum = EXCLUDED.orders_bonus_granted_sum,
        order_processing_fee     = EXCLUDED.order_processing_fee,
        restaurant_reward_sum    = EXCLUDED.restaurant_reward_sum
    RETURNING settlement_date
)
-- 5. Сдвигаем дату прогресса в cdm.srv_wf_settings
UPDATE cdm.srv_wf_settings
SET workflow_settings = json_build_object(
    'last_settlement_date', 
    (SELECT COALESCE(MAX(settlement_date), (SELECT last_date FROM settings)) FROM restaurant_aggr)
)
WHERE workflow_key = 'load_dds_to_cdm';
