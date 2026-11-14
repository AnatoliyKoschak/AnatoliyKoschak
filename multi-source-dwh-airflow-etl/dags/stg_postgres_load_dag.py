import os
import sys
import json
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator

sys.path.insert(0, os.path.dirname(__file__))
from lib import ConnectionBuilder

DAG_PATH = os.path.dirname(__file__)

default_args = {
    'owner': 'dwh_team',
    'depends_on_past': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=2),
}


def load_postgres_table_to_stg(extract_file: str, insert_file: str, **kwargs):
    """Общая функция для полного/инкрементального переноса справочников из Postgres-источника в STG"""
    task_id = kwargs['task_instance'].task_id
    pg_source = ConnectionBuilder.pg_conn("PG_ORIGIN_BONUS_SYSTEM_CONNECTION")
    pg_dwh = ConnectionBuilder.pg_conn("PG_WAREHOUSE_CONNECTION")
    
    with open(os.path.join(DAG_PATH, f"dml/{extract_file}"), "r") as f:
        extract_sql = f.read()
    with open(os.path.join(DAG_PATH, f"dml/{insert_file}"), "r") as f:
        insert_sql = f.read()
        
    with pg_source.client() as src_conn:
        with src_conn.cursor() as src_cur:
            src_cur.execute(extract_sql)
            rows = src_cur.fetchall()
            
    print(f"[EXTRACT] Таска '{task_id}': Извлечено {len(rows)} строк из источника.")

    if not rows:
        return

    records_written = 0
    with pg_dwh.connection() as dwh_conn:
        with dwh_conn.cursor() as dwh_cur:
            for row in rows:
                dwh_cur.execute(insert_sql, row)
                records_written += 1
                
    print(f"[LOAD] Таска '{task_id}': Успешно записано/обновлено {records_written} записей в DWH.")


def load_postgres_events_to_stg(**kwargs):
    """Инкрементальный перенос лога Outbox (событий бонусов) с логированием srv_wf_settings"""
    workflow_key = "stg_load_bonussystem_events"
    
    pg_source = ConnectionBuilder.pg_conn("PG_ORIGIN_BONUS_SYSTEM_CONNECTION")
    pg_dwh = ConnectionBuilder.pg_conn("PG_WAREHOUSE_CONNECTION")
    
    # 1. Читаем и выводим в лог текущие настройки из srv_wf_settings
    with pg_dwh.connection() as dwh_conn:
        with dwh_conn.cursor() as dwh_cur:
            dwh_cur.execute("""
                INSERT INTO stg.srv_wf_settings (workflow_key, workflow_settings)
                VALUES (%s, '{"last_event_id": 0}')
                ON CONFLICT (workflow_key) DO NOTHING;
            """, (workflow_key,))
            
            dwh_cur.execute("""
                SELECT workflow_settings::TEXT 
                FROM stg.srv_wf_settings 
                WHERE workflow_key = %s;
            """, (workflow_key,))
            
            current_settings_str = dwh_cur.fetchone()[0]

    print(f"[METADATA] Текущие настройки для '{workflow_key}': {current_settings_str}")
    
    current_settings = json.loads(current_settings_str)
    last_event_id = int(current_settings["last_event_id"])

    # 2. Запрашиваем инкремент из системы-источника
    with pg_source.client() as src_conn:
        with src_conn.cursor() as src_cur:
            with open(os.path.join(DAG_PATH, "dml/extract_bonus_events.sql"), "r") as f:
                extract_sql = f.read()
            src_cur.execute(extract_sql, (last_event_id,))
            events = src_cur.fetchall()
            
    print(f"[EXTRACT] Найдено {len(events)} новых событий в outbox источника начиная с ID {last_event_id}")

    if not events:
        print(f"[EXTRACT] Загрузка логов не требуется. Новых событий нет.")
        return

    max_event_id = last_event_id
    records_inserted = 0

    # 3. Идемпотентно записываем данные в STG DWH
    with pg_dwh.connection() as dwh_conn:
        with dwh_conn.cursor() as dwh_cur:
            with open(os.path.join(DAG_PATH, "dml/insert_bonus_events.sql"), "r") as f:
                insert_sql = f.read()
                
            for event in events:
                event_id, event_ts, event_type, event_value = event
                dwh_cur.execute(insert_sql, event)
                
                records_inserted += 1
                if event_id > max_event_id:
                    max_event_id = event_id
            
            # 4. Обновляем стейт workflow_settings
            new_settings_json = json.dumps({"last_event_id": max_event_id})
            dwh_cur.execute("""
                UPDATE stg.srv_wf_settings 
                SET workflow_settings = %s 
                WHERE workflow_key = %s;
            """, (new_settings_json, workflow_key))
            
            print(f"[METADATA] Новые настройки для '{workflow_key}' успешно сохранены: {new_settings_json}")
                
    print(f"[LOAD] Успешно скопировано и добавлено {records_inserted} событий в 'stg.bonussystem_events'")


with DAG(
    dag_id='stg_load_from_postgresql',
    default_args=default_args,
    description='Загрузка справочников и Outbox логов из Postgres в STG слой',
    schedule_interval='*/15 * * * *',
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'stg', 'postgres'],
) as dag:

    begin = EmptyOperator(task_id='begin')

    stg_bonus_ranks = PythonOperator(
        task_id='load_stg_bonussystem_ranks',
        python_callable=load_postgres_table_to_stg,
        op_kwargs={'extract_file': 'extract_ranks.sql', 'insert_file': 'insert_ranks.sql'},
    )

    stg_bonus_users = PythonOperator(
        task_id='load_stg_bonussystem_users',
        python_callable=load_postgres_table_to_stg,
        op_kwargs={'extract_file': 'extract_users.sql', 'insert_file': 'insert_users.sql'},
    )

    stg_bonus_events = PythonOperator(
        task_id='load_stg_bonussystem_events',
        python_callable=load_postgres_events_to_stg,
    )

    begin >> [stg_bonus_ranks, stg_bonus_users, stg_bonus_events]
