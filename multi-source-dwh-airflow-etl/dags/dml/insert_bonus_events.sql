INSERT INTO stg.bonussystem_events (id, event_ts, event_type, event_value)
VALUES (%s, %s, %s, %s)
ON CONFLICT (id) DO NOTHING;
