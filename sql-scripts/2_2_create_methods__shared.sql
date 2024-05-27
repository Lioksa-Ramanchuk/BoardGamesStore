-- получить товары каталога
create or replace procedure GetCatalog(
  p_cur out sys_refcursor,
  p_f_title in Items.title%type default null,
  p_f_publisher in Items.publisher%type default null,
  p_f_in_stock in int default 0,
  p_f_category in Items.category%type default null,
  p_ordering in varchar2 default 'last_added',
  p_account_id in Accounts.id%type default null
) is
  f_title Items.title%type := case when p_f_title is null then null else trim(p_f_title) end;
  f_publisher Items.publisher%type := case when p_f_publisher is null then null else trim(p_f_publisher) end;
  f_category Items.category%type := case when p_f_category is null then null else trim(p_f_category) end;
begin
  open p_cur for 
    select 
        id, title, price, image, 
        (case when count > 0 then 1 else 0 end) as is_in_stock, 
        is_available,
        (case when p_account_id is not null and exists (select 1 from Favourites f where f.account_id = p_account_id and f.item_id = i.id) then 1 else 0 end) as is_in_favs,
        (case when p_account_id is not null and exists (select 1 from Carts c where c.account_id = p_account_id and c.item_id = i.id) then 1 else 0 end) as is_in_cart
      from Items i
      where 
        (f_title is null or title like f_title||'%') and
        (f_publisher is null or publisher like f_publisher||'%') and
        (p_f_in_stock = 0 or (is_available = 1 and count > 0)) and
        (f_category is null or category like f_category||'%')
      order by case
          when p_ordering = 'price_asc' then price
          when p_ordering = 'price_desc' then -price
          else -id
        end;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить полную информацию о товаре
create or replace procedure GetItemInfo(
  p_item_id in Items.id%type,
  p_account_id in int default null,
  p_title out Items.title%type,
  p_price out Items.price%type,
  p_count out Items.count%type,
  p_image out Items.image%type,
  p_description out Items.description%type,
  p_category out Items.category%type,
  p_publisher out Items.publisher%type,
  p_year out Items.year%type,
  p_min_players out Items.min_players%type,
  p_max_players out Items.max_players%type,
  p_play_time out Items.play_time%type,
  p_player_min_age out Items.player_min_age%type,
  p_is_available out number,
  p_is_in_favs out number,
  p_is_in_cart out number
) is
begin
  select 
      title, price, count, image, 
      description, category, 
      publisher, year, 
      min_players, max_players, 
      play_time, player_min_age,
      is_available,
      (case when p_account_id is not null and exists (select 1 from Favourites f where f.account_id = p_account_id and f.item_id = i.id) then 1 else 0 end) as is_in_favs,
      (case when p_account_id is not null and exists (select 1 from Carts c where c.account_id = p_account_id and c.item_id = i.id) then 1 else 0 end) as is_in_cart
    into
      p_title, p_price, p_count, p_image,
      p_description, p_category,
      p_publisher, p_year,
      p_min_players, p_max_players,
      p_play_time, p_player_min_age,
      p_is_available, p_is_in_favs, p_is_in_cart
    from Items i
    where id = p_item_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить полную информацию о заказе
create or replace procedure GetOrderInfo(
  p_order_id in Orders.id%type,
  p_order_number out Orders.order_number%type,
  p_order_date out Orders.order_date%type,
  p_os_name out OrderStatuses.os_name%type,
  p_order_comment out varchar2, 
  p_order_cost out decimal,
  p_client_fullname out varchar2, 
  p_client_email out varchar2,
  p_client_address out varchar2,
  p_card_number out varchar2
) is
  r_key AccountsKeys.key%type;
begin
  select ak.key into r_key
    from Orders o join AccountsKeys ak on o.account_id = ak.account_id
    where o.id = p_order_id;
  select 
      order_number, order_date, os_name, 
      DecryptAES128(order_comment, r_key),
      GetOrderCost(id),
      DecryptAES128(client_fullname, r_key), 
      DecryptAES128(client_email, r_key),
      DecryptAES128(client_address, r_key),
      GetCardNumber(card_number, r_key)
    into
      p_order_number, p_order_date, p_os_name, p_order_comment, p_order_cost,
      p_client_fullname, p_client_email, p_client_address, p_card_number
    from V_Orders
    where id = p_order_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить список товаров в заказе
create or replace procedure GetOrderItems(
  p_order_id in Orders.id%type,
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select 
      id, title, price, count, image
    from V_OrderedItems
    where order_id = p_order_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить сведения аккаунта
create or replace procedure GetAccountInfo(
  p_id in Accounts.id%type,
  p_login out Accounts.login%type,
  p_fullname out varchar2,
  p_email out varchar2
) is
  r_key AccountsKeys.key%type;
begin
  select key into r_key from AccountsKeys where account_id = p_id;
  select login, DecryptAES128(fullname, r_key), DecryptAES128(email, r_key)
    into p_login, p_fullname, p_email
    from Accounts
    where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- обновить сведения аккаунта
create or replace procedure UpdateAccountInfo(
  p_id in Accounts.id%type,
  p_login in varchar2,
  p_password in varchar2,
  p_fullname in varchar2,
  p_email in varchar2
) is
  r_old_login Accounts.login%type;
  LOGIN_ALREADY_EXISTS_EXCEPTION exception;
  pragma exception_init(LOGIN_ALREADY_EXISTS_EXCEPTION, -20001);
  r_key AccountsKeys.key%type;
begin
  if p_login is not null then
    select login into r_old_login from Accounts where id = p_id;
    if p_login != r_old_login and AccountExists(p_login) then
      raise_application_error(-20001, 'LOGIN_ALREADY_EXISTS_EXCEPTION');
    end if;
  end if;

  select key into r_key from AccountsKeys where account_id = p_id;
  update Accounts
    set
      login = case when p_login is null then login else p_login end,
      password = case when p_password is null then password else HashMD5(p_password) end,
      fullname = case when  p_fullname is null then fullname else EncryptAES128(p_fullname, r_key) end,
      email = case when p_email is null then email else EncryptAES128(p_email, r_key) end
    where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- деактивировать аккаунт клиента
create or replace procedure DeactivateClientAccount(
  p_account_id in Accounts.id%type
) is
begin
  delete from Favourites where account_id = p_account_id;
  delete from Carts where account_id = p_account_id;
  DeactivateAccount(p_account_id);
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/