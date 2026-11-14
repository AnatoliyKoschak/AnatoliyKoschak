DROP TABLE IF EXISTS dwh.load_dates_craftsman_report_datamart;

CREATE TABLE IF NOT EXISTS dwh.load_dates_craftsman_report_datamart (
    id bigint generated always as identity constraint load_dates_craftsman_report_datamart_pk primary key,
    load_dttm date not null
);