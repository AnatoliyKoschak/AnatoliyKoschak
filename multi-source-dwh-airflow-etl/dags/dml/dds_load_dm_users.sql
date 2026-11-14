WITH settings AS (
    SELECT (workflow_settings->>'last_update_ts')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings WHERE workflow_key = 'load_users_to_dds'
),
src AS (
    SELECT object_id AS user_id, (object_value::JSONB) ->> 'name' AS user_name, (object_value::JSONB) ->> 'login' AS user_login, update_ts
    FROM stg.ordersystem_users, settings WHERE update_ts > settings.last_ts
),
do_upsert AS (
    INSERT INTO dds.dm_users (user_id, user_name, user_login)
    SELECT user_id, user_name, user_login FROM src
    ON CONFLICT (user_id) DO UPDATE SET user_name = EXCLUDED.user_name, user_login = EXCLUDED.user_login
)
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object('last_update_ts', (SELECT COALESCE(MAX(update_ts), (SELECT last_ts FROM settings)) FROM src))
WHERE workflow_key = 'load_users_to_dds';
