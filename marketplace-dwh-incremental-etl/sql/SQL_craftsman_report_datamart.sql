WITH
dwh_delta AS (
	SELECT 	
	dc.craftsman_id,	
	dc.craftsman_name,	
	dc.craftsman_address, 
	dc.craftsman_birthday,	
	dc.craftsman_email,	
	fo.order_id,	
	fo.product_id,	
	dp.product_price,	
	dp.product_type,	
	date_part('year', age(dcs.customer_birthday)) as customer_age,	
	fo.order_completion_date - fo.order_created_date as diff_order_date,	 
	fo.order_status,	
	to_char(fo.order_created_date, 'yyyy-mm') as report_period,	
	crd.craftsman_id::text::bool as exist_craftsman_id,	
	dc.load_dttm as craftsman_load_dttm,	
	dcs.load_dttm as customers_load_dttm,	
	dp.load_dttm as products_load_dttm
FROM dwh.f_order fo 
	INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
	INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id  
	INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id 
	LEFT JOIN dwh.craftsman_report_datamart crd ON fo.craftsman_id = crd.craftsman_id  
WHERE fo.load_dttm > (
    select coalesce(max(load_dttm), '1900-01-01') 
    from dwh.load_dates_craftsman_report_datamart
    ) 
	or dc.load_dttm > (
       select coalesce(max(load_dttm), '1900-01-01') 
    from dwh.load_dates_craftsman_report_datamart
    )
    or dcs.load_dttm > (
       select coalesce(max(load_dttm), '1900-01-01') 
    from dwh.load_dates_craftsman_report_datamart
    )
	or dp.load_dttm > (
       select coalesce(max(load_dttm), '1900-01-01') 
    from dwh.load_dates_craftsman_report_datamart
    ) ;
),
dwh_update_delta AS (
	SELECT 	
		dd.craftsman_id	
	FROM dwh_delta dd 
	where dd.exist_craftsman_id is not null
),
dwh_delta_insert_result AS (
	SELECT  
		T4.craftsman_id AS craftsman_id,
		T4.craftsman_name AS craftsman_name,
		T4.craftsman_address AS craftsman_address,
		T4.craftsman_birthday AS craftsman_birthday,
		T4.craftsman_email AS craftsman_email,
		T4.craftsman_money AS craftsman_money,
		T4.platform_money AS platform_money,
		T4.count_order AS count_order,
		T4.avg_price_order AS avg_price_order,
		T4.avg_age_customer AS avg_age_customer,
		T4.product_type AS top_product_category,
		T4.median_time_order_completed AS median_time_order_completed,
		T4.count_order_created AS count_order_created,
		T4.count_order_in_progress AS count_order_in_progress,
		T4.count_order_delivery AS count_order_delivery,
		T4.count_order_done AS count_order_done,
		T4.count_order_not_done AS count_order_not_done,
		T4.report_period AS report_period 
	FROM (
		SELECT 	 -- чтобы определить самую популярную категорию товаров
			*,
			RANK() OVER(PARTITION BY T2.craftsman_id ORDER BY count_product DESC) AS rank_count_product 
		FROM ( 
			SELECT  -- кроме столбца с самой популярной категорией товаров у мастера. Для этого столбца сделаем отдельную выборку с другой группировкой и выполним join
				craftsman_id, 
				craftsman_name, 
				craftsman_address, 
				craftsman_birthday, 
				craftsman_email, 
				sum(product_price) * 0.9 as craftsman_money,
				sum(product_price) * 0.1 as platform_money,
				count(order_id) as count_order, 
				avg(product_price) as avg_price_order, 
				avg(customer_age) as avg_age_customer, 
				percentile_cont(0.5) WITHIN GROUP(ORDER BY diff_order_date) as median_time_order_completed, 
				sum(case when order_status = 'created' then 1 else 0 end) as count_order_created, 
				sum(case when order_status = 'in progress' then 1 else 0 end) as count_order_in_progress, 
				sum(case when order_status = 'delivery' then 1 else 0 end) as count_order_delivery, 
				sum(case when order_status = 'done' then 1 else 0 end) as count_order_done,	
				sum(case when order_status != 'done' then 1 else 0 end) as count_order_not_done,	
				report_period 
			FROM dwh_delta AS T1
			WHERE T1.exist_craftsman_id IS NULL
			GROUP BY T1.craftsman_id, T1.craftsman_name, T1.craftsman_address, T1.craftsman_birthday, T1.craftsman_email, T1.report_period
			) AS T2 
				INNER JOIN (
					SELECT 	 -- которая и покажет самую популярную категорию товаров у мастера
						dd.craftsman_id as craftsman_id_for_product_type, 
						dd.product_type, 
						count (dd.product_id ) as count_product
					FROM dwh_delta AS dd
					GROUP BY dd.craftsman_id, dd.product_type
					ORDER BY count_product DESC) AS T3 ON T2.craftsman_id = T3.craftsman_id_for_product_type
		) AS T4 WHERE T4.rank_count_product = 1 ORDER BY report_period -- условие помогает оставить в выборке первую по популярности категорию товаров
),
dwh_delta_update_result AS (
	SELECT 
		T4.craftsman_id AS craftsman_id,
		T4.craftsman_name AS craftsman_name,
		T4.craftsman_address AS craftsman_address,
		T4.craftsman_birthday AS craftsman_birthday,
		T4.craftsman_email AS craftsman_email,
		T4.craftsman_money AS craftsman_money,
		T4.platform_money AS platform_money,
		T4.count_order AS count_order,
		T4.avg_price_order AS avg_price_order,
		T4.avg_age_customer AS avg_age_customer,
		T4.product_type AS top_product_category,
		T4.median_time_order_completed AS median_time_order_completed,
		T4.count_order_created AS count_order_created,
		T4.count_order_in_progress AS count_order_in_progress,
		T4.count_order_delivery AS count_order_delivery, 
		T4.count_order_done AS count_order_done, 
		T4.count_order_not_done AS count_order_not_done,
		T4.report_period AS report_period 
	FROM (
		SELECT 	 -- чтобы определить самую популярную категорию товаров
			*,
			RANK() OVER(PARTITION BY T2.craftsman_id ORDER BY count_product DESC) AS rank_count_product 
		FROM (
			SELECT  -- кроме столбца с самой популярной категорией товаров у мастера. Для этого столбца сделаем отдельную выборку с другой группировкой и выполним join
				T1.craftsman_id AS craftsman_id,
				T1.craftsman_name AS craftsman_name,
				T1.craftsman_address AS craftsman_address,
				T1.craftsman_birthday AS craftsman_birthday,
				T1.craftsman_email AS craftsman_email,
				SUM(T1.product_price) - (SUM(T1.product_price) * 0.1) AS craftsman_money,
				SUM(T1.product_price) * 0.1 AS platform_money,
				COUNT(order_id) AS count_order,
				AVG(T1.product_price) AS avg_price_order,
				AVG(T1.customer_age) AS avg_age_customer,
				PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY diff_order_date) AS median_time_order_completed,
				SUM(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created, 
				SUM(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress, 
				SUM(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery, 
				SUM(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done, 
				SUM(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
				T1.report_period AS report_period
			FROM (
				SELECT 	-- которые уже присутствуют в витрине
					dc.craftsman_id AS craftsman_id,
					dc.craftsman_name AS craftsman_name,
					dc.craftsman_address AS craftsman_address,
					dc.craftsman_birthday AS craftsman_birthday,
					dc.craftsman_email AS craftsman_email,
					fo.order_id AS order_id,
					dp.product_id AS product_id,
					dp.product_price AS product_price,
					dp.product_type AS product_type,
					date_part('year', age(dcs.customer_birthday)) as customer_age, 
					fo.order_completion_date - fo.order_created_date as diff_order_date, 
					fo.order_status AS order_status, 
					to_char(fo.order_created_date, 'yyyy-mm') as report_period
				FROM dwh.f_order fo 
					INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
					INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
					INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id
					INNER JOIN dwh_update_delta ud ON fo.craftsman_id = ud.craftsman_id
			) AS T1
			GROUP BY 
				T1.craftsman_id, T1.craftsman_name, T1.craftsman_address, T1.craftsman_birthday, T1.craftsman_email, T1.report_period
		) AS T2 
		INNER JOIN (
			SELECT 	--  которая и покажет самую популярную категорию товаров у мастера
				dd.craftsman_id as craftsman_id_for_product_type, 
				dd.product_type, 
				count (dd.product_id ) as count_product
			FROM dwh_delta AS dd
			GROUP BY dd.craftsman_id, dd.product_type
			ORDER BY count_product DESC
		) AS T3 ON T2.craftsman_id = T3.craftsman_id_for_product_type
	) AS T4 WHERE T4.rank_count_product = 1 ORDER BY report_period
),
insert_delta AS (
	insert into  dwh.craftsman_report_datamart (
		craftsman_id
		, craftsman_name 
		, craftsman_address
		, craftsman_birthday 
		, craftsman_email 
		, craftsman_money 
		, platform_money 
		, count_order 
		, avg_price_order 
		, avg_age_customer 
		, top_product_category 
		, median_time_order_completed 
		, count_order_created 
		, count_order_in_progress 
		, count_order_delivery 
		, count_order_done 
		, count_order_not_done 
		, report_period 
	
	)
	select
		craftsman_id
		, craftsman_name 
		, craftsman_address
		, craftsman_birthday 
		, craftsman_email 
		, craftsman_money 
		, platform_money 
		, count_order 
		, avg_price_order 
		, avg_age_customer 
		, top_product_category 
		, median_time_order_completed 
		, count_order_created 
		, count_order_in_progress 
		, count_order_delivery 
		, count_order_done 
		, count_order_not_done 
		, report_period 
	from dwh_delta_insert_result
),
update_delta AS (
	UPDATE dwh.craftsman_report_datamart SET
		 craftsman_name = tableB.craftsman_name
		, craftsman_address = tableB.craftsman_address
		, craftsman_birthday = tableB.craftsman_birthday 
		, craftsman_email = tableB.craftsman_email 
		, craftsman_money = tableB.craftsman_money 
		, platform_money = tableB.platform_money 
		, count_order = tableB.count_order 
		, avg_price_order = tableB.avg_price_order 
		, avg_age_customer = tableB.avg_age_customer 
		, top_product_category = tableB.top_product_category 
		, median_time_order_completed = tableB.median_time_order_completed 
		, count_order_created = tableB.count_order_created 
		, count_order_in_progress = tableB.count_order_in_progress 
		, count_order_delivery = tableB.count_order_delivery 
		, count_order_done = tableB.count_order_done 
		, count_order_not_done = tableB.count_order_not_done
		, report_period = tableB.report_period 
	FROM (
		select
			craftsman_id
			, craftsman_name 
			, craftsman_address
			, craftsman_birthday 
			, craftsman_email 
			, craftsman_money 
			, platform_money 
			, count_order 
			, avg_price_order 
			, avg_age_customer 
			, top_product_category 
			, median_time_order_completed 
			, count_order_created 
			, count_order_in_progress 
			, count_order_delivery 
			, count_order_done 
			, count_order_not_done 
			, report_period 
		from dwh_delta_update_result
		) AS tableB
	WHERE dwh.craftsman_report_datamart.craftsman_id = tableB.craftsman_id
),
insert_load_date AS (
	INSERT INTO dwh.load_dates_craftsman_report_datamart (
		load_dttm
	)
	
	select greatest(coalesce(max(craftsman_load_dttm), now()), coalesce(max(customers_load_dttm), now()), coalesce(max(products_load_dttm), now()))
	FROM dwh_delta
)
SELECT 'increment datamart';