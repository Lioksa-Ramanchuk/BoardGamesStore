-- ! - получить сведения всех аккаунтов
create or replace procedure sys_Get_Accounts (
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select a.id, a.role_id, a.login, a.password, a.is_active, 
        DecryptAES128(fullname, ak.key), DecryptAES128(email, ak.key)
      from Accounts a join AccountsKeys ak on a.id = ak.account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - удалить аккаунт
create or replace procedure sys_Delete_Account (
  p_id in accounts.id%type
) is
begin
  delete from Accounts where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - получить всю клиентскую информацию аккаунтов
create or replace procedure sys_Get_Clients (
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select c.id, c.account_id, DecryptAES128(address, ak.key)
      from Clients c join AccountsKeys ak on c.account_id = ak.account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - получить содержимое всех корзин пользователей
create or replace procedure sys_Get_Carts (
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select id, account_id, item_id, count
      from Carts;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить новый возможный статус заказа
create or replace procedure sys_Add_OrderStatus(
  p_os_name in OrderStatuses.os_name%type
) is
begin
  insert into OrderStatuses(os_name) values (p_os_name);
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - удалить возможный статус заказа
create or replace procedure sys_Delete_OrderStatus(
  p_id in OrderStatuses.id%type
) is
begin
  delete from OrderStatuses where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - изменить возможный статус заказа
create or replace procedure sys_Update_OrderStatus(
  p_id in OrderStatuses.id%type,
  p_os_name in OrderStatuses.os_name%type
) as
begin
  update OrderStatuses set os_name = p_os_name where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - изменить данные заказа
create or replace procedure sys_UpdateOrder(
  p_id in orders.id%type,
  p_account_id in orders.account_id%type,
  p_order_number in orders.order_number%type,
  p_order_date in orders.order_date%type,
  p_status_id in orders.status_id%type,
  p_order_comment in varchar2,
  p_card_number in varchar2,
  p_client_fullname in varchar2,
  p_client_email in varchar2,
  p_client_address in varchar2
) as
  r_order Orders%rowtype;
  r_key AccountsKeys.key%type;
begin
  select * into r_order
    from Orders where id = p_id;
  select key into r_key from AccountsKeys where account_id = r_order.account_id;
  update Orders
    set account_id = coalesce(p_account_id, r_order.account_id),
        order_number = coalesce(p_order_number, r_order.order_number),
        order_date = coalesce(p_order_date, r_order.order_date),
        status_id = coalesce(p_status_id, r_order.status_id),
        order_comment = case when p_order_comment is null then r_order.order_comment else EncryptAES128(p_order_comment, r_key) end,
        card_number = case when p_card_number is null then r_order.card_number else EncryptAES128(p_card_number, r_key) end,
        client_fullname = case when p_client_fullname is null then r_order.client_fullname else EncryptAES128(p_client_fullname, r_key) end,
        client_email = case when p_client_email is null then r_order.client_email else EncryptAES128(p_client_email, r_key) end,
        client_address = case when p_client_address is null then r_order.client_address else EncryptAES128(p_client_address, r_key) end
    where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - удалить заказ из истории заказов
create or replace procedure sys_DeleteOrder(
  p_id in Orders.id%type
) is
begin
  delete from Orders where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - получить информацию о всех заказах
create or replace procedure sys_GetOrders(
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select o.id, o.account_id, o.order_number, o.order_date, o.status_id, 
         DecryptAES128(o.order_comment, key) as order_comment, 
         DecryptAES128(o.card_number, key) as card_number, 
         DecryptAES128(o.client_fullname, key) as client_fullname, 
         DecryptAES128(o.client_email, key) as client_email, 
         DecryptAES128(o.client_address, key) as client_address
      from Orders o join AccountsKeys ak on o.account_id = ak.account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - добавить новый заказанный товар
create or replace procedure sys_Add_OrderedItem(
  p_order_id in OrderedItems.order_id%type,
  p_item_id in OrderedItems.item_id%type,
  p_price in OrderedItems.price%type,
  p_count in OrderedItems.count%type
) is
begin
  insert into OrderedItems(order_id, item_id, price, count)
    values (p_order_id, p_item_id, p_price, p_count);
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - удаление заказанного товара
create or replace procedure sys_Delete_OrderedItem(
  p_id in OrderedItems.id%type
) is
begin
  delete from OrderedItems where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/

-- ! - изменить информацию о заказанном товаре
create or replace procedure sys_Update_OrderedItem(
  p_id in OrderedItems.id%type,
  p_price in OrderedItems.price%type,
  p_count in OrderedItems.count%type
) is
begin
  update OrderedItems
    set 
      price = coalesce(p_price, price),
      count = coalesce(p_count, count)
    where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить список всех заказанных товаров
create or replace procedure sys_Get_OrderedItems(
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select id, order_id, item_id, price, count
      from OrderedItems;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- ! - получить список всех избранных товаров пользователей
create or replace procedure sys_Get_Favs(
  p_cur out sys_refcursor
) is
begin
  open p_cur for select id, account_id, item_id from Favourites;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/