--Запрос на удаление MATERIALIZED VIEW. Применять можно при необходимости
--DROP MATERIALIZED VIEW IF EXISTS dwh.orders_report_materialized_view;

CREATE MATERIALIZED VIEW IF NOT EXISTS dwh.orders_report_materialized_view
AS
select 	
	sum(T1.product_price) as total_money,	-- сумма денег по всем заказам
	count(T1.product_name) as total_products, -- количество заказанных товаров
	avg(T1.craftsman_age) as avg_age_craftsman, -- средний возраст мастера
	avg(T1.customer_age) as avg_age_customer, -- средний возраст заказчика
	sum(case when T1.order_status = 'created' then 1 else 0 end) as count_order_created, -- количество созданных заказов
	sum(case when T1.order_status = 'in progress' then 1 else 0 end) as count_order_in_progress, -- количество заказов в процессе изготовки
	sum(case when T1.order_status = 'delivery' then 1 else 0 end) as count_order_delivery, -- количество заказов в доставке
	sum(case when T1.order_status = 'done' then 1 else 0 end) as count_order_done, -- количество завершённых заказов
	sum(case when T1.order_status != 'done' then 1 else 0 end) as count_order_not_done, -- количество незавершённых заказов
	avg(T2.diff_order_date) as avg_days_complete_orders, -- среднее количество дней на выполнение заказа
	percentile_cont(0.5) within group(order by T2.diff_order_date) as median_days_complete_orders, -- медианное количество дней на выполнение заказа
	T1.report_period -- отчётный месяц
from
	(
	select 	
		fo.order_id, -- идентификатор заказа
		fo.order_completion_date, -- дата исполнения заказа
		fo.order_created_date, -- дата создания заказа
		dp.product_price, -- цена товара
		dp.product_name, -- название товара
		fo.order_status, -- статус выполнения заказа
		to_char(fo.order_created_date , 'yyyy-mm') as report_period, -- год и месяц, по которому будет происходить группировка
		date_part('year', age(dc2.craftsman_birthday)) as craftsman_age, -- возраст мастера
		date_part('year', age(dc.customer_birthday)) as customer_age -- возраст заказчика
	from
		dwh.f_order fo
	inner join dwh.d_craftsman dc2 on
		fo.craftsman_id = dc2.craftsman_id -- присоединяем к заказам информацию по мастерам
	inner join dwh.d_customer dc on
		fo.customer_id = dc.customer_id -- присоединяем к заказам информацию по заказчикам
	inner join dwh.d_product dp on
		fo.product_id = dp.product_id -- присоединяем к заказам информацию по товарам
	) as T1
	-- даём имя T1 таблице, полученной из вложенного запроса выше
left join (
	-- присоединяем таблицу со сроками в днях по всем заказам из вложенного запроса ниже
	select 	
		inner_fo.order_id, -- идентификатор заказа, чтобы выполнить join с таблицей T1
		inner_fo.order_completion_date - inner_fo.order_created_date as diff_order_date -- количество дней от момента создания заказа до его выполнения
	from
		dwh.f_order inner_fo
	where
		-- из списка всех заказов берём только те, которые завершились и у которых есть дата завершения заказа, чтобы избежать неполных данных в записях
		inner_fo.order_completion_date is not null
		) as T2 on
	-- даём имя вложенной таблице с количеством дней на заказ T2 и присоединяем её по order_id к таблице T1
	t1.order_id = t2.order_id
	-- группируем по месяцам итоговую таблицу
group by
	report_period
	-- сортируем по сумме денег
order by
	total_money
;
-- Запрос, который проверяет, что отчёт не пустой со строкой-примером данных                
-- SELECT * FROM dwh.orders_report_materialized_view limit 1;