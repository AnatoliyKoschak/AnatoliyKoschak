/*
увеличить цены на капучино на 20%.
Обновить данные по ценам так, чтобы до завершения обновления никто не вносил других изменений в цены этих заведений. 
В заведениях, где цены не меняются, данные о меню должны остаться в полном доступе.
*/
begin;

select * -- блокируем только выбранные строки
from cafe.restaurants r
where r.menu @?'$.Кофе.Капучино'
for update
;

with cte as (
select r.restaurant_uuid, (r.menu #> '{Кофе,Капучино}')::int as price
from cafe.restaurants r
where r.menu @?'$.Кофе.Капучино'
)
update cafe.restaurants r set menu = jsonb_set(r.menu, '{Кофе,Капучино}', to_jsonb(cte.price * 1.2))
from cte
where r.restaurant_uuid = cte.restaurant_uuid
;

commit;


/*
сделать единый номер телефонов для всех менеджеров. 
Новый номер — 8-800-2500-***, где порядковый номер менеджера выставляется по алфавиту, начиная с номера 100. 
Старый и новый номер нужно будет хранить в массиве, где первый элемент массива — новый номер, а второй — старый.
Во время проведения этих изменений таблица managers должна быть недоступна для изменений со стороны других пользователей, но доступна для чтения.
*/
begin;

lock table cafe.managers in SHARE UPDATE exclusive MODE;

alter table cafe.managers  rename column manager_phone to old_phone;

alter table cafe.managers  add column manager_phone text[];

with new_phones as (
select
	m.manager_uuid,
	array[concat('8-800-2500-', 100 + row_number() over(order by m.manager)), m.old_phone ] as new_phones
from cafe.managers m
)
update cafe.managers m set manager_phone = n.new_phones
from new_phones n
where m.manager_uuid  = n.manager_uuid
;

alter table cafe.managers drop column old_phone;

commit;


