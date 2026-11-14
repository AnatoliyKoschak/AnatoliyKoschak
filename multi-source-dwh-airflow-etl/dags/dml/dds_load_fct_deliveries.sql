WITH settings AS (
    SELECT (workflow_settings->>'last_delivery_ts')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings 
    WHERE workflow_key = 'load_deliveries_to_dds'
),
src_deliveries AS (
    SELECT 
        d.object_id AS delivery_id,
        (d.object_value::JSONB) ->> 'courier_id' AS src_courier_id,
        (d.object_value::JSONB) ->> 'order_id' AS src_order_id,
        ((d.object_value::JSONB) ->> 'order_ts')::TIMESTAMP AS order_ts,
        d.delivery_ts,
        (d.object_value::JSONB) ->> 'address' AS address,
        ((d.object_value::JSONB) ->> 'rate')::INTEGER AS rate,
        ((d.object_value::JSONB) ->> 'sum')::NUMERIC(14, 2) AS sum,
        ((d.object_value::JSONB) ->> 'tip_sum')::NUMERIC(14, 2) AS tip_sum
    FROM stg.api_deliveries d
    CROSS JOIN settings
    WHERE d.delivery_ts > settings.last_ts
),
do_upsert AS (
    INSERT INTO dds.fct_deliveries (
        delivery_id, 
        courier_id, 
        order_id, 
        order_ts, 
        delivery_ts, 
        address, 
        rate, 
        sum, 
        tip_sum
    )
    SELECT 
        sd.delivery_id,
        c.id AS courier_id,
        o.id AS order_id,
        sd.order_ts,
        sd.delivery_ts,
        sd.address,
        sd.rate,
        sd.sum,
        sd.tip_sum
    FROM src_deliveries sd
    JOIN dds.dm_couriers c ON c.courier_id = sd.src_courier_id
    JOIN dds.dm_orders o ON o.order_key = sd.src_order_id
    ON CONFLICT (delivery_id) DO UPDATE 
    SET 
        courier_id  = EXCLUDED.courier_id,
        order_id    = EXCLUDED.order_id,
        order_ts    = EXCLUDED.order_ts,
        delivery_ts = EXCLUDED.delivery_ts,
        address     = EXCLUDED.address,
        rate        = EXCLUDED.rate,
        sum         = EXCLUDED.sum,
        tip_sum     = EXCLUDED.tip_sum
    RETURNING delivery_ts
)
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object(
    'last_delivery_ts', 
    (SELECT COALESCE(MAX(delivery_ts), (SELECT last_ts FROM settings)) FROM src_deliveries)
)
WHERE workflow_key = 'load_deliveries_to_dds';
