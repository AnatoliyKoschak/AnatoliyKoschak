from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.operators.empty import EmptyOperator

default_args = {
    'owner': 'dwh_team',
    'depends_on_past': True,
    'retries': 3,
    'retry_delay': timedelta(minutes=10),
}

with DAG(
    dag_id='cdm_load_courier_ledger',
    default_args=default_args,
    description='Ежемесячный расчёт витрины выплат курьерам с управлением через srv_wf_settings',
    schedule_interval='0 4 10 * *',  # 10-го числа каждого месяца в 04:00
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'cdm', 'couriers'],
) as dag:

    begin = EmptyOperator(task_id='begin')

    # Авто-инициализация изолированной настройки для витрины курьеров
    init_cdm_courier_settings = PostgresOperator(
        task_id='init_cdm_courier_settings',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql="""
            INSERT INTO cdm.srv_wf_settings (workflow_key, workflow_settings)
            VALUES ('load_courier_ledger_to_cdm', '{"last_settlement_month": "2026-01-01"}')
            ON CONFLICT (workflow_key) DO NOTHING;
        """,
    )

    # Расчёт витрины выплат
    cdm_courier_ledger = PostgresOperator(
        task_id='load_cdm_dm_courier_ledger',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/cdm_load_dm_courier_ledger.sql',
    )

    begin >> init_cdm_courier_settings >> cdm_courier_ledger
