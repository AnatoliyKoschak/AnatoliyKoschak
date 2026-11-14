-- DDL витрины данных
DROP TABLE IF EXISTS dwh.customer_report_datamart;

create table dwh.customer_report_datamart (
	id int8 generated always as identity not null,
	-- Идентификатор записи
	customer_id int8 not null,
	-- Идентификатор заказчика
	customer_name varchar not null,
	-- Ф.И.О. заказчика
	customer_address varchar not null,
	-- Адрес заказчика
	customer_birthday date not null,
	-- Дата рождения заказчика
	customer_email varchar not null,
	-- Электронная почта заказчика
	customer_money numeric(15, 2) not null,
	-- Сумма, которую потратил заказчик
	platform_money numeric(15, 2) not null,
	-- сумма, которую заработала платформа от покупок заказчика за месяц (10% от суммы, которую потратил заказчик)
	count_order int8 not null,
	-- количество заказов у заказчика за месяц
	avg_price_order numeric(10, 2) not null,
	-- средняя стоимость одного заказа у заказчика за месяц
	median_time_order_completed numeric(10, 1),
	-- медианное время в днях от момента создания заказа до его завершения за месяц
	top_product_category varchar not null,
	-- самая популярная категория товаров у этого заказчика за месяц
	top_craftsman_id int8 not null,
	-- идентификатор самого популярного мастера ручной работы у заказчика
	count_order_created int8 default 0 not null,
	-- количество созданных заказов за месяц
	count_order_in_progress int8 default 0 not null,
	-- количество заказов в процессе изготовки за месяц
	count_order_delivery int8 default 0 not null,
	-- количество заказов в доставке за месяц
	count_order_done int8 default 0 not null,
	-- количество завершённых заказов за месяц
	count_order_not_done int8 default 0 not null,
	-- количество незавершённых заказов за месяц
	report_period varchar null,
	-- отчётный период, год и месяц
	constraint customer_report_datamart_pkey primary key (id)
);
-- Column comments

comment on
column dwh.customer_report_datamart.id is 'Идентификатор записи';

comment on
column dwh.customer_report_datamart.customer_id is 'Идентификатор заказчика';

comment on
column dwh.customer_report_datamart.customer_name is 'Ф.И.О. заказчика';

comment on
column dwh.customer_report_datamart.customer_address is 'Адрес заказчика';

comment on
column dwh.customer_report_datamart.customer_birthday is 'Дата рождения заказчика';

comment on
column dwh.customer_report_datamart.customer_email is 'Электронная почта заказчика';

comment on
column dwh.customer_report_datamart.customer_money is 'Сумма, которую потратил заказчик';

comment on
column dwh.customer_report_datamart.platform_money is 'сумма, которую заработала платформа от покупок заказчика за месяц (10% от суммы, которую потратил заказчик)';

comment on
column dwh.customer_report_datamart.count_order is 'количество заказов у заказчика за месяц';

comment on
column dwh.customer_report_datamart.avg_price_order is 'средняя стоимость одного заказа у заказчика за месяц';

comment on
column dwh.customer_report_datamart.median_time_order_completed is 'медианное время в днях от момента создания заказа до его завершения за месяц';

comment on
column dwh.customer_report_datamart.top_product_category is 'самая популярная категория товаров у этого заказчика за месяц';

comment on
column dwh.customer_report_datamart.top_craftsman_id is 'идентификатор самого популярного мастера ручной работы у заказчика';

comment on
column dwh.customer_report_datamart.count_order_created is 'количество созданных заказов за месяц';

comment on
column dwh.customer_report_datamart.count_order_in_progress is 'количество заказов в процессе изготовки за месяц';

comment on
column dwh.customer_report_datamart.count_order_delivery is 'количество заказов в доставке за месяц';

comment on
column dwh.customer_report_datamart.count_order_done is 'количество завершённых заказов за месяц';

comment on
column dwh.customer_report_datamart.count_order_not_done is 'количество незавершённых заказов за месяц';

comment on
column dwh.customer_report_datamart.report_period is 'отчётный период, год и месяц';
