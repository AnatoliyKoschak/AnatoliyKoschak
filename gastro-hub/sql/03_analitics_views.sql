-- топ 3 заведений внутри каждого типа по среднему чеку
create or replace view cafe.v_top3_by_type(cafe_name, type, avg_check)
as
with cte as (
select r.restaurant_uuid, r."type",
	round(avg(s.avg_check), 2) as avg_check,
	row_number() over(partition by r.type order by avg(s.avg_check) desc) as rn
from cafe.restaurants r
join cafe.sales s
	on s.restaurant_uuid = r.restaurant_uuid
group by r."type", r.restaurant_uuid
)
select r.cafe_name, r."type", cte.avg_check
from cte
join cafe.restaurants r
	on cte.restaurant_uuid = r.restaurant_uuid
where rn <= 3
order by r."type", cte.rn
;


-- средний чек для каждого заведения от года к году за все года
create materialized view cafe.v_avg_check_diff
as
with cte as(
select extract('year' from s.date) as year,
	r.cafe_name,
	r.type,
	round(avg(s.avg_check),2) as avg_check
from cafe.sales s
join cafe.restaurants r
	on r.restaurant_uuid = s.restaurant_uuid
where extract('year' from s.date) != 2023
group by year, r.cafe_name, r.type
)
, with_avg as(
select  year, cafe_name, type, avg_check,
	lag(avg_check) over(partition by cafe_name order by year) as avg_check_prev
from cte
)
select year, cafe_name, type, avg_check, avg_check_prev,
	round(avg_check_prev * 100 / avg_check - 100, 2) as avg_check_diff
from with_avg
order by cafe_name, year
;
