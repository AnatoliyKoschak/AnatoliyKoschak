from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.operators.empty import EmptyOperator

default_args = {
    'owner': 'dwh_team',
    'depends_on_past': True,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    dag_id='cdm_load_settlement_report',
    default_args=default_args,
    description='Автономный инкрементальный расчет витрины расчетов с ресторанами (CDM)',
    schedule_interval='15 * * * *',  # Запуск каждый час на 15-й минуте (после DDS)
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'cdm'],
) as dag:

    begin = EmptyOperator(task_id='begin')

    # Автоматическая инициализация настройки при первом старте
    init_cdm_settings = PostgresOperator(
        task_id='init_cdm_workflow_settings',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql="""
            INSERT INTO cdm.srv_wf_settings (workflow_key, workflow_settings)
            VALUES ('load_dds_to_cdm', '{"last_settlement_date": "2026-01-01"}')
            ON CONFLICT (workflow_key) DO NOTHING;
        """,
    )

    cdm_settlement_report = PostgresOperator(
        task_id='load_cdm_dm_settlement_report',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/cdm_load_dm_settlement_report.sql',
    )

    begin >> init_cdm_settings >> cdm_settlement_report
