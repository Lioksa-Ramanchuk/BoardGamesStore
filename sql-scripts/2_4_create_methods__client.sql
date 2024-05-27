-- получить список товаров в корзине пользователя
create or replace procedure GetCartItems(
  p_account_id in Accounts.id%type,
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select 
        id, title, price, cart_count, image, 
        (case when count > 0 then 1 else 0 end) as is_in_stock,
        is_available,
        (case when exists (select 1 from Favourites f where f.account_id = p_account_id and f.item_id = f.id) then 1 else 0 end) as is_in_favs
      from V_CartItems
      where account_id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить список товаров в избранном пользователя
create or replace procedure GetFavsItems(
  p_account_id in Accounts.id%type,
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select 
        id, title, price, image,
        (case when count > 0 then 1 else 0 end) as is_in_stock, 
        is_available,
        (case when exists (select 1 from Carts c where c.account_id = p_account_id and c.item_id = f.id) then 1 else 0 end) as is_in_cart
      from V_FavsItems f
      where account_id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- обновить количество товара в корзине пользователя
create or replace procedure UpdateCartItemCount(
  p_account_id in Accounts.id%type,
  p_item_id in Items.id%type,
  p_count in out Carts.count%type
) is
  r_is_available Items.is_available%type;
  r_item_count Items.count%type;
  r_count int;
begin
  select is_available, count
    into r_is_available, r_item_count
    from Items
    where id = p_item_id;
  if r_is_available = 0 then
    delete 
      from Carts
      where account_id = p_account_id and item_id = p_item_id;
    p_count := 0;
    return;
  end if;
  
  if p_count > 0 then
    if r_item_count = 0 then
      p_count := 0;
      return;
    end if;
    
    select count(*) 
      into r_count 
      from Carts 
      where account_id = p_account_id and item_id = p_item_id; 
    if r_count = 0 then
      insert into Carts(account_id, item_id, count) 
        values (p_account_id, p_item_id, p_count);
    else
      update Carts 
        set count = p_count 
        where account_id = p_account_id and item_id = p_item_id;
    end if;
  else
    delete 
      from Carts
      where account_id = p_account_id and item_id = p_item_id;
    p_count := 0;
  end if;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить/исключить товар из избранного пользователя
create or replace procedure ToggleItemInFavs(
  p_account_id in Accounts.id%type,
  p_item_id in Items.id%type,
  p_is_in_favs out boolean
) is
  r_is_in_favs boolean;
begin
  r_is_in_favs := ItemIsInFavs(p_account_id, p_item_id);
  if r_is_in_favs then
    delete from Favourites
      where account_id = p_account_id and item_id = p_item_id;
  else
    insert into Favourites(account_id, item_id) 
      values (p_account_id, p_item_id);
  end if;
  p_is_in_favs := not r_is_in_favs;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить товар в избранное
create or replace function AddToFavs(
  p_account_id in Favourites.account_id%type,
  p_item_id in Favourites.item_id%type
) return number as
  r_count number;
begin
  select count(*) into r_count from Favourites where account_id = p_account_id and item_id = p_item_id;
  if r_count = 0 then
    insert into Favourites(account_id, item_id) values (p_account_id, p_item_id);
    return 1;
  else
    return 0;
  end if;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- исключить товар из избранного
create or replace procedure RemoveFromFavs(
  p_account_id in Favourites.account_id%type,
  p_item_id in Favourites.item_id%type
) as
begin
  delete from Favourites where account_id = p_account_id and item_id = p_item_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить/исключить товар из корзины пользователя
create or replace procedure ToggleItemInCart(
  p_account_id in Accounts.id%type,
  p_item_id in Items.id%type,
  p_is_in_cart out boolean
) is
  r_count int;
begin
  r_count := case when ItemIsInCart(p_account_id, p_item_id) 
    then 0 else 1 end;
  UpdateCartItemCount(p_account_id, p_item_id, r_count);
  p_is_in_cart := case when r_count = 0 then false else true end;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить товар в корзину пользователя
create or replace procedure AddToCart (
  p_account_id in Carts.account_id%type,
  p_item_id in Carts.item_id%type,
  p_count in Carts.count%type default 1,
  p_rows_added out number
) as
begin
  select count(*) into p_rows_added from Carts
    where account_id = p_account_id and item_id = p_item_id;
  if p_rows_added = 0 then
    insert into Carts (account_id, item_id, count) 
      values (p_account_id, p_item_id, p_count);
    p_rows_added := 1;
  else
    p_rows_added := 0;
  end if;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- исключить товар из корзины пользователя
create or replace procedure RemoveFromCart (
  p_account_id in Carts.account_id%type,
  p_item_id in Carts.item_id%type
) as
begin
  delete from Carts 
    where account_id = p_account_id and item_id = p_item_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- удостовериться, что корзина товаров может быть заказана
create or replace procedure ValidateCart(
  p_account_id in Carts.account_id%type
) is
begin
  if CartIsEmpty(p_account_id) then
    raise_application_error(-20002, 'CART_IS_EMPTY_EXCEPTION');
  end if;
  if CartContainsInvalidItems(p_account_id) then
    raise_application_error(-20003, 'CART_CONTAINS_INVALID_ITEMS_EXCEPTION');
  end if;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- оформить заказ
create or replace procedure MakeOrder(
  p_account_id in Orders.account_id%type,
  p_order_comment in varchar2,
  p_card_number in varchar2,
  p_order_id out Orders.id%type
) is
  r_order_date Orders.order_date%type;
  r_os_id Orders.status_id%type;
  r_client_fullname raw(2000);
  r_client_email raw(2000);
  r_client_address raw(2000);
  r_key AccountsKeys.key%type;
begin
  ValidateCart(p_account_id);
  
  select fullname, email, address
    into r_client_fullname, r_client_email, r_client_address
    from V_ClientAccountsInfo
    where id = p_account_id;
  select sys_extract_utc(SYSTIMESTAMP) into r_order_date from dual;
  select id into r_os_id from OrderStatuses where os_name = 'PROCESSING';
  select key into r_key from AccountsKeys where account_id = p_account_id;
  insert into Orders(
      account_id, order_number,
      order_date, status_id, 
      client_fullname, client_email, client_address, 
      order_comment, card_number
    ) values (
      p_account_id, GenerateOrderNumber(),
      r_order_date, r_os_id, 
      r_client_fullname, r_client_email, r_client_address,
      EncryptAES128(p_order_comment, r_key),
      EncryptAES128(p_card_number, r_key)
    ) returning id into p_order_id;

  for cart_record in (
    select id, account_id, price, cart_count
      from V_CartItems
      where account_id = p_account_id
  ) loop
    insert into OrderedItems(order_id, item_id, price, count)
      values (
        p_order_id, 
        cart_record.id, 
        cart_record.price,
        cart_record.cart_count
      );
  end loop;
  delete from Carts where account_id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить список заказов пользователя
create or replace procedure GetClientOrdersList(
  p_account_id in Accounts.id%type,
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select 
        id, order_number, order_date, os_name
      from V_Orders
      where account_id = p_account_id
      order by order_date desc;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить клиентские сведения аккаунта пользователя
create or replace procedure GetClientAccountInfo(
  p_id in Accounts.id%type,
  p_address out varchar2
) is
  r_key AccountsKeys.key%type;
begin
  select key into r_key from AccountsKeys where account_id = p_id;
  select DecryptAES128(address, r_key)
    into p_address
    from V_ClientAccountsInfo
    where id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- обновить клиентские сведения аккаунта пользователя
create or replace procedure UpdateClientAccountInfo(
  p_id in Accounts.id%type,
  p_address varchar2
) is
  r_key AccountsKeys.key%type;
begin
  select key into r_key from AccountsKeys where account_id = p_id;
  update Clients
    set address = case when p_address is null then address else EncryptAES128(p_address, r_key) end
    where account_id = p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить стоимость корзины пользователя
create or replace procedure GetCartCost(
  p_account_id in Accounts.id%type,
  p_cart_cost out decimal
) is
begin
  select coalesce(sum(price * cart_count), 0)
    into p_cart_cost
    from V_CartItems
    where account_id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- переместить избранные товары в корзину
create or replace procedure MoveFavsToCart(
  p_account_id in accounts.id%type
) is
  r_count int;
begin
  for fav in (select id, is_available, count from V_FavsItems where account_id = p_account_id) loop
    if fav.is_available = 1 and fav.count > 0 then
      select count(*) into r_count from Carts
        where account_id = p_account_id and item_id = fav.id;
      if r_count = 0 then
        insert into Carts (account_id, item_id, count)
          values (p_account_id, fav.id, 1);
      end if;
      delete from Favourites
        where item_id = fav.id and account_id = p_account_id;
    end if;
  end loop;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- очистить избранное пользователя
create or replace procedure ClearFavs(
  p_account_id in accounts.id%type
) is
begin
  delete from Favourites where account_id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- очистить корзину пользователя
create or replace procedure ClearCart(
  p_account_id in accounts.id%type
) is
begin
  delete from Carts where account_id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/