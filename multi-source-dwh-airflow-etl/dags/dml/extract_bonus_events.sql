SELECT 
    id, 
    event_ts, 
    event_type, 
    event_value 
FROM public.outbox
WHERE id > %s
ORDER BY id ASC;
