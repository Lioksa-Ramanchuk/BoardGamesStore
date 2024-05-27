--ORCLCDB, sys as SYSDBA

-- создать PDB
create pluggable database BGAMESSTORE 
  admin user SYSADMIN identified by SYSADMIN_PASSWORD roles = (DBA)
  file_name_convert = ('/opt/oracle/oradata/ORCLCDB/pdbseed/', '/opt/oracle/oradata/ORCLCDB/BGAMESSTORE/');
alter pluggable database BGAMESSTORE open;
--------------------------------------------------

-- позволить пользователю БД SYSADMIN вызывать методы DBMS_CRYPTO
alter session set CONTAINER = BGAMESSTORE;
grant execute on sys.DBMS_CRYPTO to SYSADMIN;
grant select any dictionary to SYSADMIN;
--------------------------------------------------

--BGAMESSTORE, SYSADMIN

-- создать табличное пространство БД
create tablespace BGS_TS
  datafile '/opt/oracle/oradata/ORCLCDB/BGAMESSTORE/BGS_TS.dbf'
  size 16M autoextend on next 16M;
alter user SYSADMIN default tablespace BGS_TS quota unlimited on BGS_TS;

-- таблица с полной информацией о товарах
create sequence items_id_seq;
create table Items(
  id int default items_id_seq.nextval not null primary key,
  title varchar2(255) not null,
  price decimal(10, 2) check(price >= 0) not null,
  count int check(count >= 0) not null,
  image varchar2(511) not null,
  description varchar2(2047) not null,
  category varchar2(255) not null,
  publisher varchar2(255) not null,
  year number(4) check(year >= 0) not null,
  min_players int check(min_players >= 0) not null,
  max_players int check(max_players >= 0) not null,
  play_time int check(play_time >= 0) not null,
  player_min_age int check(player_min_age >= 0) not null,
  is_available number(1) default 1 check(is_available in (0, 1)) not null,
  constraint chk_players_range check (max_players >= min_players)
) tablespace BGS_TS;

-- таблица со списком ролей пользователей БД
create sequence roles_id_seq;
create table Roles(
  id int default roles_id_seq.nextval not null primary key,
  role_name varchar2(255) not null
) tablespace BGS_TS;

-- таблица со сведениями об аккаунтах
create sequence accounts_id_seq;
create table Accounts (
  id int default accounts_id_seq.nextval not null primary key,
  role_id int not null references Roles(id) on delete cascade,
  login varchar2(255) not null,
  password raw(2000) not null,
  is_active number(1) default 1 check(is_active in (0, 1)) not null,
  fullname raw(2000) not null,
  email raw(2000) not null
) tablespace BGS_TS;

-- таблица с клиентской информацией аккаунтов
create sequence clients_id_seq;
create table Clients (
  id int default accounts_id_seq.nextval not null primary key,
  account_id int not null references Accounts(id) on delete cascade unique,
  address raw(2000) not null
) tablespace BGS_TS;

-- таблица с ключами шифрования аккаунтов
create sequence account_keys_id_seq;
create table AccountsKeys (
  id int default account_keys_id_seq.nextval not null primary key,
  account_id int not null references Accounts(id) on delete cascade unique,
  key raw(128) not null
) tablespace BGS_TS;

-- таблица с товарами, добавленными пользователями в корзину
create sequence carts_id_seq;
create table Carts (
  id int default carts_id_seq.nextval not null primary key,
  account_id int not null references Accounts(id) on delete cascade,
  item_id int not null references Items(id) on delete cascade,
  count int default 1 check(count > 0) not null
) tablespace BGS_TS;

-- таблица со списком возможных статусов заказа
create sequence order_statuses_id_seq;
create table OrderStatuses (
  id int default order_statuses_id_seq.nextval not null primary key,
  os_name varchar2(255) not null
) tablespace BGS_TS;

-- таблица с информацией о заказах пользователей
create sequence orders_id_seq;
create table Orders (
  id int default orders_id_seq.nextval not null primary key,
  account_id int not null references Accounts(id) on delete cascade,
  order_number varchar2(255) not null,
  order_date date not null,
  status_id int not null references OrderStatuses(id) on delete cascade,
  order_comment raw(2000),
  card_number raw(2000) not null,
  client_fullname raw(2000) not null,
  client_email raw(2000) not null,
  client_address raw(2000) not null
) tablespace BGS_TS;

-- таблица с информацией о заказанных товарах
create sequence ordered_items_id_seq;
create table OrderedItems (
  id int default ordered_items_id_seq.nextval not null primary key,
  order_id int not null references Orders(id) on delete cascade,
  item_id int not null references Items(id) on delete cascade,
  price decimal(10, 2) check(price >= 0) not null,
  count int check(count > 0) not null
) tablespace BGS_TS;

-- таблица с товарами, добавленными пользователями в избранное
create sequence favourites_id_seq;
create table Favourites (
  id int default favourites_id_seq.nextval not null primary key,
  account_id int not null references Accounts(id) on delete cascade,
  item_id int not null references Items(id) on delete cascade
) tablespace BGS_TS;
--------------------------------------------------

-- активные аккаунты
create or replace view V_ActiveAccounts as
  select * from Accounts where is_active = 1;
  
-- более подробная информация о заказе
create or replace view V_Orders as
  select 
      o.id, o.account_id, o.order_number, o.order_date, os.os_name, o.order_comment, 
      o.client_fullname, o.client_email, o.client_address, o.card_number
    from Orders o join OrderStatuses os on o.status_id = os.id;
    
-- более подробная информация о заказанных товарах
create or replace view V_OrderedItems as
  select i.id, oi.order_id, i.title, oi.price, oi.count, i.image
    from OrderedItems oi join Items i on oi.item_id = i.id;
    
-- более подробная информация о товарах в корзине
create or replace view V_CartItems as
  select i.id, c.account_id, i.title, i.price, i.count, c.count as cart_count, i.image, i.is_available
    from Carts c join Items i on c.item_id = i.id;

-- более подробная информация о товарах в избранном
create or replace view V_FavsItems as
  select i.id, f.account_id, i.title, i.price, i.count, i.image, i.is_available
    from Favourites f join Items i on f.item_id = i.id;
    
---- более подробная информация об аккаунте клиента
create or replace view V_ClientAccountsInfo as
  select a.id, a.fullname, a.email, c.address
    from Accounts a join Clients c on c.account_id = a.id;
    
-- аккаунты с ролями
create or replace view V_AccountsWithRoles as
  select a.id, a.login, r.role_name
    from V_ActiveAccounts a join Roles r on a.role_id = r.id;
--------------------------------------------------

-- заполнение таблиц Roles и OrderStatuses начальными значениями
insert into Roles(role_name) values ('GUESTROLE');    -- гость
insert into Roles(role_name) values ('CLIENTROLE');   -- пользователь (клиент)
insert into Roles(role_name) values ('ADMINROLE');    -- администратор
insert into Roles(role_name) values ('PDB_DBS');      -- системный администратор
commit;
insert into OrderStatuses(os_name) values ('PROCESSING'); -- в обработке
insert into OrderStatuses(os_name) values ('SHIPPED');    -- отправлен
insert into OrderStatuses(os_name) values ('DELIVERED');  -- доставлен
insert into OrderStatuses(os_name) values ('CANCELLED');  -- отменён
insert into OrderStatuses(os_name) values ('RETURNED');   -- возвращён
commit;
--------------------------------------------------

-- создать директорию для работы с XML-данными
--$ mkdir /opt/oracle/oradata/ORCLCDB/BGAMESSTORE/XML
create or replace directory BGAMESSTORE_XML as '/opt/oracle/oradata/ORCLCDB/BGAMESSTORE/XML';
--------------------------------------------------