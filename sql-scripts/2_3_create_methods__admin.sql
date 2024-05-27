-- добавить нового администратора
create or replace procedure CreateNewAdminAccount(
  p_login in Accounts.login%type,
  p_password in varchar2,
  p_fullname in varchar2,
  p_email in varchar2,
  p_account_id out Accounts.id%type
) is
  r_role_id Roles.id%type;
begin
  if AccountExists(p_login) then
    raise_application_error(-20001, 'LOGIN_ALREADY_EXISTS_EXCEPTION');
  end if;
  select id into r_role_id from Roles where role_name = 'ADMINROLE';
  CreateAccount(
    r_role_id, p_login, p_password, p_fullname, p_email,
    p_account_id
  );
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- деактивировать аккаунт администратора
create or replace procedure DeactivateAdminAccount(
  p_account_id in Accounts.id%type
) is
begin
  DeactivateAccount(p_account_id);
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- добавить товар в каталог
create or replace procedure AddItem(
  p_title in Items.title%type,
  p_price in Items.price%type,
  p_count in Items.count%type,
  p_image in Items.image%type,
  p_description in Items.description%type,
  p_category in Items.category%type,
  p_publisher in Items.publisher%type,
  p_year in Items.year%type,
  p_min_players in Items.min_players%type,
  p_max_players in Items.max_players%type,
  p_play_time in Items.play_time%type,
  p_player_min_age in Items.player_min_age%type,
  p_is_available in Items.is_available%type,
  p_id out Items.id%type
) is
begin
  insert into Items(
      title, price, count, 
      image, description, category, 
      publisher, year, 
      min_players, max_players, 
      play_time, player_min_age, is_available
    ) values (
      p_title, p_price, p_count,
      p_image, p_description, p_category, 
      p_publisher, p_year,
      p_min_players, p_max_players, 
      p_play_time, p_player_min_age, p_is_available
    ) returning id into p_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- обновить информацию о товаре
create or replace procedure UpdateItem(
  p_id in Items.id%type,
  p_title in Items.title%type,
  p_price in Items.price%type,
  p_count in Items.count%type,
  p_image in Items.image%type,
  p_description in Items.description%type,
  p_category in Items.category%type,
  p_publisher in Items.publisher%type,
  p_year in Items.year%type,
  p_min_players in Items.min_players%type,
  p_max_players in Items.max_players%type,
  p_play_time in Items.play_time%type,
  p_player_min_age in Items.player_min_age%type,
  p_is_available in Items.is_available%type
) is
begin
  update Items
    set
      title = case when p_title is null then title else p_title end,
      price = case when p_price is null then price else p_price end,
      count = case when p_count is null then count else p_count end,
      image = case when p_image is null then image else p_image end,
      description = case when p_description is null then description else p_description end,
      category = case when p_category is null then category else p_category end,
      publisher = case when p_publisher is null then publisher else p_publisher end,
      year = case when p_year is null then year else p_year end,
      min_players = case when p_min_players is null then min_players else p_min_players end,
      max_players = case when p_max_players is null then max_players else p_max_players end,
      play_time = case when p_play_time is null then play_time else p_play_time end,
      player_min_age = case when p_player_min_age is null then player_min_age else p_player_min_age end,
      is_available = case when p_is_available is null then is_available else p_is_available end
    where id = p_id;
  if p_is_available = 0 then
    MakeItemUnavailable(p_id);
  end if;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- задать статус заказа
create or replace procedure SetOrderStatus(
  p_order_id in Orders.id%type,
  p_new_os_name in OrderStatuses.os_name%type
) is
  r_os_id OrderStatuses.id%type;
begin
  select id
    into r_os_id
    from OrderStatuses
    where os_name = p_new_os_name;
  update Orders
    set status_id = r_os_id
    where id = p_order_id;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить список возможных статусов заказа
create or replace procedure GetOrderStatuses (
  p_ref_cursor out sys_refcursor
) as
begin
  open p_ref_cursor for 
    select id, os_name from OrderStatuses;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- получить список всех заказов
create or replace procedure GetAllOrdersList(
  p_cur out sys_refcursor
) is
begin
  open p_cur for 
    select 
        id, order_number, order_date, os_name
      from V_Orders
      order by order_date desc;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- записать каталог в XML-файл
create or replace procedure ExportItemsToXML (
  p_filename in varchar2
) is
  r_xml_data clob;
  r_file_handle utl_file.file_type;
begin
  select
      xmlelement("items", xmlagg(xmlelement("item", xmlforest(
          id as "id", title as "title", price as "price", count as "count", image as "image", description as "description", 
          category as "category", publisher as "publisher", year as "year", min_players as "min_players", max_players as "max_players", 
          play_time as "play_time", player_min_age as "player_min_age", is_available as "is_available"
      )))).getClobVal()
    into r_xml_data
    from Items;
    
  r_file_handle := utl_file.fopen('BGAMESSTORE_XML', p_filename, 'w', 32767);
  utl_file.put(r_file_handle, r_xml_data);
  utl_file.fclose(r_file_handle);
exception
  when others then
    raise_application_error(-20005, 'EXPORT_TO_XML_EXCEPTION: '||SQLERRM);
end;
/
-- добавить товары из XML-файла в каталог
create or replace procedure ImportItemsFromXML(
  p_filename in varchar2
) is
  r_xml_data clob;
  r_items_xml xmltype;
  r_file_handle utl_file.file_type;
  buffer varchar2(32767);
begin
  r_file_handle := utl_file.fopen('BGAMESSTORE_XML', p_filename, 'r', 32767);
  loop
    begin
      utl_file.get_line(r_file_handle, buffer);
      r_xml_data := r_xml_data || buffer;
    exception
      when NO_DATA_FOUND then
        exit;
    end;
  end loop;
  utl_file.fclose(r_file_handle);
  r_items_xml := xmltype(r_xml_data);
  for item in (select *
        from xmltable('/items/item' passing r_items_xml columns 
            title varchar2(255) path 'title', price decimal(10, 2) path 'price',
            count int path 'count', image varchar2(511) path 'image', 
            description varchar2(2047) path 'description', category varchar2(255) path 'category', 
            publisher varchar2(255) path 'publisher', year number(4) path 'year', 
            min_players int path 'min_players', max_players int path 'max_players', 
            play_time int path 'play_time', player_min_age int path 'player_min_age',
            is_available number(1) path 'is_available')) loop
  insert into Items (
      title, price, count, image, description, category, publisher, year,
      min_players, max_players, play_time, player_min_age, is_available
    ) values (
      item.title, item.price, item.count, item.image, item.description, 
      item.category, item.publisher, item.year, item.min_players, item.max_players, 
      item.play_time, item.player_min_age, item.is_available
    );
  end loop;
exception
  when others then
    raise_application_error(-20006, 'IMPORT_FROM_XML_EXCEPTION: '||SQLERRM);
end;
/