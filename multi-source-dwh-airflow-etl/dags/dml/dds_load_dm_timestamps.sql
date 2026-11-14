WITH settings AS (
    SELECT (workflow_settings->>'last_update_ts')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings WHERE workflow_key = 'load_timestamps_to_dds'
),
filtered_orders AS (
    SELECT DISTINCT
        date_trunc('second', st.dttm::TIMESTAMP) AS ts, o.update_ts
    FROM stg.ordersystem_orders o CROSS JOIN settings
    CROSS JOIN LATERAL jsonb_to_recordset((o.object_value::JSONB) -> 'statuses') AS st(status TEXT, dttm TEXT)
    WHERE st.dttm::TIMESTAMP > settings.last_ts
      AND (o.object_value::JSONB) ->> 'final_status' IN ('CLOSED', 'CANCELLED')
      AND st.status = (o.object_value::JSONB) ->> 'final_status' AND st.dttm IS NOT NULL
),
do_insert AS (
    INSERT INTO dds.dm_timestamps (ts, year, month, day, time, date)
    SELECT ts, EXTRACT(YEAR FROM ts)::SMALLINT, EXTRACT(MONTH FROM ts)::SMALLINT, EXTRACT(DAY FROM ts)::SMALLINT, ts::TIME, ts::DATE FROM filtered_orders
    ON CONFLICT (ts) DO NOTHING
)
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object('last_update_ts', (SELECT COALESCE(MAX(update_ts), (SELECT last_ts FROM settings)) FROM filtered_orders))
WHERE workflow_key = 'load_timestamps_to_dds';
