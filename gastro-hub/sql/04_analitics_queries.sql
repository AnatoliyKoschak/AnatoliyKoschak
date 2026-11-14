-- самая дорогая пицца для каждой пиццерии
with cte as (
select r.cafe_name, pizza.pizza, pizza.price::int as price,
	row_number() over(partition by r.restaurant_uuid order by pizza.price::int desc) as rn
from cafe.restaurants r, jsonb_each_text(r.menu -> 'Пицца') as pizza(pizza, price)
where r.menu ? 'Пицца'
)
select cafe_name, pizza, price
from cte
where rn = 1
order by cafe_name
;

-- пиццерия с самым большим количеством пицц в меню
with pizza as (
select r.restaurant_uuid, r.cafe_name,  jsonb_each_text(r.menu -> 'Пицца') as pizza
from cafe.restaurants r
where r.menu ? 'Пицца'
)
, rank as (
select p.cafe_name,
	count(*) as cnt,
	dense_rank() over(order by count(*) desc) as rank
from pizza p
group by p.restaurant_uuid , p.cafe_name
)
select cafe_name, cnt
from rank r
where r.rank = 1
order by cafe_name
;

-- топ-3 заведения, где чаще всего менялся менеджер за весь период
with cte as (
select r.cafe_name,
	count(rmwd.manager_uuid) as cnt,
	rank() over(order by count(rmwd.manager_uuid) desc) as rank
from cafe.restaurant_manager_work_dates rmwd
join cafe.restaurants r
	on rmwd.restaurant_uuid = r.restaurant_uuid
group by r.restaurant_uuid
)
select cafe_name, cnt
from  cte
where rank <= 3
order by rank, cafe_name
;