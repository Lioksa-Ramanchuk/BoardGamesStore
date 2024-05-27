commit;
declare
  v_id Items.id%type;
begin
  for i in 1..200000 loop
    SYSADMIN.AddItem('title'||i, 100, 100, 
      '/images/items/default.png', 'description', 
      'category'||i, 'publisher'||i, 
      2023, 1, 10, 60, 6, 0, v_id);
  end loop;
end;
/
select count(*) from Items;
--
create index ITEMS_FULL_FILTER_INDEX on Items(title, publisher, category);
--
select id, title, price, image, is_available
  from Items
  where 
    title like 'title7777%' and
    publisher like 'publisher7777%' and
    category like 'category7777%'
  order by -id;
--
rollback;