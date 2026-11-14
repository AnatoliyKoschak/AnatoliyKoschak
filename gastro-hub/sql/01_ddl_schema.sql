
drop schema if exists cafe cascade;

create schema cafe;

create type cafe.restaurant_type as enum (
	'coffee_shop',
	'restaurant',
	'bar',
	'pizzeria'
);

create table cafe.restaurants(
	restaurant_uuid uuid primary key default gen_random_uuid(),
	cafe_name varchar not null,
	type cafe.restaurant_type not null,
	menu jsonb
);

create table cafe.managers(
	manager_uuid uuid primary key default gen_random_uuid(),
	manager varchar not null,
	manager_phone varchar
);

create table cafe.restaurant_manager_work_dates(
	restaurant_uuid uuid not null references cafe.restaurants(restaurant_uuid),
	manager_uuid uuid not null references cafe.managers(manager_uuid),
	date_start date not null,
	date_end date check (date_end is null or date_end >= date_start ),
	primary key (restaurant_uuid, manager_uuid)
);

create table cafe.sales(
	date date not null,
	restaurant_uuid uuid not null references cafe.restaurants(restaurant_uuid),
	avg_check numeric(6,2),
	primary key (restaurant_uuid, "date")
);
