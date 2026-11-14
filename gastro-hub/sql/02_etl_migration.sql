with managers as (
select distinct on (s.manager, s.manager_phone)
	gen_random_uuid() as manager_uuid,
	s.manager,
	s.manager_phone
from raw_data.sales s
)
insert into cafe.managers
select m.manager_uuid,
	m.manager,
	m.manager_phone
from managers m
;

with restaurants as (
select distinct on (s.cafe_name)
	gen_random_uuid() as restaurant_uuid,
	s.cafe_name,
	s."type"::cafe.restaurant_type as "type",
	m.menu
from raw_data.sales s
full join raw_data.menu m
	on s.cafe_name = m.cafe_name
)
insert into cafe.restaurants(restaurant_uuid, cafe_name, "type", menu)
select r.restaurant_uuid,
	r.cafe_name,
	r."type",
	r.menu
from restaurants r
;

with  restaurant_manager_work_dates as (
select r.restaurant_uuid, m.manager_uuid,
	min(s.report_date) as date_start,
	max(s.report_date) as date_end
from raw_data.sales s
join cafe.restaurants r
	on s.cafe_name  = r.cafe_name
join cafe.managers m
	on s.manager = m.manager
		and s.manager_phone  = m.manager_phone
group by r.restaurant_uuid, m.manager_uuid
)
insert into cafe.restaurant_manager_work_dates
select rm.restaurant_uuid, rm.manager_uuid, rm.date_start, rm.date_end
from restaurant_manager_work_dates rm
;

with sales as (
select s.report_date  as date,
	r.restaurant_uuid,
	s.avg_check
from raw_data.sales s
join cafe.restaurants r
	on s.cafe_name  = r.cafe_name
)
insert into cafe.sales
select s.date, s.restaurant_uuid, s.avg_check
from sales s
;
