-- хэшировать строку
create or replace function HashMD5(p_text in varchar2) 
return raw is
begin
  return DBMS_CRYPTO.hash(
    UTL_I18N.string_to_raw(p_text, 'AL32UTF8'),
    DBMS_CRYPTO.HASH_MD5
  );
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- зашифровать строку ключом (AES128)
create or replace function EncryptAES128(
  p_text in varchar2,
  p_key in raw
) return raw is
begin
  return DBMS_CRYPTO.encrypt(
    UTL_I18N.string_to_raw(p_text, 'AL32UTF8'),
    DBMS_CRYPTO.ENCRYPT_AES128 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5,
    p_key
  );
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- дешифровать строку ключом (AES128)
create or replace function DecryptAES128(
  p_encrypted in raw,
  p_key in raw
) return varchar2 is 
begin 
  return UTL_I18N.raw_to_char( 
    DBMS_CRYPTO.decrypt( 
      p_encrypted, 
      DBMS_CRYPTO.ENCRYPT_AES128 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5,
      p_key 
    ), 
    'AL32UTF8' 
  );
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить аккаунт
create or replace procedure CreateAccount(
  p_role_id in Accounts.role_id%type,
  p_login in Accounts.login%type,
  p_password in varchar2,
  p_fullname in varchar2,
  p_email in varchar2,
  p_account_id out Accounts.id%type
) is
  r_key AccountsKeys.key%type;
  e_duplicate_login exception;
begin
  r_key := DBMS_CRYPTO.randombytes(16);
  insert into Accounts(role_id, login, password, fullname, email)
    values (
      p_role_id,
      p_login,
      HashMD5(p_password),
      EncryptAES128(p_fullname, r_key),
      EncryptAES128(p_email, r_key)
    ) returning id into p_account_id;
  insert into AccountsKeys(account_id, key)
    values (p_account_id, r_key);
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- деактивировать аккаунт
create or replace procedure DeactivateAccount(
  p_account_id in Accounts.id%type
) is
begin
  update Accounts set is_active = 0 where id = p_account_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- сгенерировать номер заказа в формате XXX_XXX_XXX
create or replace function GenerateOrderNumber
return varchar2 is
begin
  return 
      DBMS_RANDOM.string('X', 3) || '_' || 
      DBMS_RANDOM.string('X', 3) || '_' ||
      DBMS_RANDOM.string('X', 3);
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- существует ли аккаунт с заданным логином (и паролем)
create or replace function AccountExists(
  p_login in Accounts.login%type,
  p_password in varchar2 default null
) return boolean is
  r_exists number(1);
  r_password raw(2000) default null;
begin
  if p_password is not null then
    r_password := HashMD5(p_password);
  end if;
  select case when exists(
        select 1 from V_ActiveAccounts
          where login = p_login and 
            (r_password is null or password = r_password)
      ) then 1 else 0 end
    into r_exists from dual;
  return r_exists != 0;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- сделать товар недоступным
create or replace procedure MakeItemUnavailable(
  p_item_id in Items.id%type
) is
begin
  delete from Carts where item_id = p_item_id;
  update Items set is_available = 0 where id = p_item_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- пуста ли корзина пользователя
create or replace function CartIsEmpty(
  p_account_id Accounts.id%type
) return boolean is
  r_count int;
begin
  select count(*) 
    into r_count 
    from Carts 
    where account_id = p_account_id;
  return r_count = 0;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- может ли товар быть заказан
create or replace function ItemCanBeOrdered(
  p_id in Items.id%type
) return int is
  r_can_be_ordered int;
begin
  select case when is_available = 1 and count > 0 then 1 else 0 end
    into r_can_be_ordered 
    from Items where id = p_id;
  return r_can_be_ordered;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- содержит ли корзина товары, которые нельзя заказать
create or replace function CartContainsInvalidItems(
  p_account_id in Accounts.id%type
) return boolean is
  r_contains_invalid_items int;
begin
  select case when exists(
        select 1 from V_CartItems
          where account_id = p_account_id and ItemCanBeOrdered(id) = 0
      ) then 1 else 0 end
    into r_contains_invalid_items from dual;
  return r_contains_invalid_items != 0;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить стоимость заказа
create or replace function GetOrderCost(
  p_order_id in Accounts.id%type
) return decimal is
  r_order_cost decimal default 0;
begin
  select sum(price * count)
    into r_order_cost
    from OrderedItems
    where order_id = p_order_id;
  return r_order_cost;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- есть ли товар в корзине пользователя
create or replace function ItemIsInCart(
  p_account_id in Accounts.id%type,
  p_item_id in Items.id%type
) return boolean is
  r_is_in_cart int;
begin
  select case when exists(
        select 1 from Carts
          where account_id = p_account_id and item_id = p_item_id
      ) then 1 else 0 end
    into r_is_in_cart from dual;
  return r_is_in_cart != 0;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- есть ли товар в избранном пользователя
create or replace function ItemIsInFavs(
  p_account_id in Accounts.id%type,
  p_item_id in Items.id%type
) return boolean is
  r_is_in_favs int;
begin
  select case when exists(
        select 1 from Favourites
          where account_id = p_account_id and item_id = p_item_id
      ) then 1 else 0 end
    into r_is_in_favs from dual;
  return r_is_in_favs != 0;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить номер карты (возможно, замаскированный)
create or replace function GetCardNumber(
  p_card_number in raw,
  p_key in AccountsKeys.key%type
) return varchar2 is
  r_card_number varchar2(255);
  r_is_admin int;
begin
  select case when exists(
      select 1 from DBA_ROLE_PRIVS 
        where grantee = USER and granted_role = 'ADMINROLE'
    ) then 1 else 0 end into r_is_admin from dual;
  select DecryptAES128(p_card_number, p_key) into r_card_number from dual;
  if r_is_admin = 1 then
    return regexp_replace(r_card_number, '(.{4})', '\1 ');
  else
    return
      regexp_replace(lpad('*', length(r_card_number) - 4, '*'), '(.{4})', '\1 ') || 
      substr(r_card_number, -4);
  end if;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/