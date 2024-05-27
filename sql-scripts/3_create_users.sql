-- роль администратора
create role AdminRole;
grant create session to AdminRole; 
--&
grant execute on GetCatalog to AdminRole;
grant execute on GetItemInfo to AdminRole;
grant execute on AddItem to AdminRole;
grant execute on UpdateItem to AdminRole;
--&
grant read, write on directory BGAMESSTORE_XML to AdminRole;
grant execute on ExportItemsToXML to AdminRole;
grant execute on ImportItemsFromXML to AdminRole;
--&
grant execute on GetAllOrdersList to AdminRole;
grant execute on GetOrderInfo to AdminRole;
grant execute on GetOrderItems to AdminRole;
grant execute on SetOrderStatus to AdminRole;
grant execute on GetOrderStatuses to AdminRole;
--&
grant execute on GetAccountInfo to AdminRole;
grant execute on UpdateAccountInfo to AdminRole;
grant execute on DeactivateAdminAccount to AdminRole;
grant execute on CreateNewAdminAccount to AdminRole;
--& // not used in app
grant execute on DeactivateClientAccount to AdminRole;
--------------------------------------------------

-- роль пользователя (клиента)
create role ClientRole;
grant create session to ClientRole;
--&
grant execute on GetCatalog to ClientRole;
grant execute on GetItemInfo to ClientRole;
--&
grant execute on GetFavsItems to ClientRole;
grant execute on ToggleItemInFavs to ClientRole;
grant execute on MoveFavsToCart to ClientRole;
grant execute on ClearFavs to ClientRole;
--&
grant execute on GetCartItems to ClientRole;
grant execute on GetCartCost to ClientRole;
grant execute on ToggleItemInCart to ClientRole;
grant execute on UpdateCartItemCount to ClientRole;
grant execute on ClearCart to ClientRole;
grant execute on ValidateCart to ClientRole;
--&
grant execute on ValidateCart to ClientRole;
grant execute on MakeOrder to ClientRole;
grant execute on GetClientOrdersList to ClientRole;
grant execute on GetOrderInfo to ClientRole;
grant execute on GetOrderItems to ClientRole;
--&
grant execute on GetAccountInfo to ClientRole;
grant execute on GetClientAccountInfo to ClientRole;
grant execute on UpdateAccountInfo to ClientRole;
grant execute on UpdateClientAccountInfo to ClientRole;
grant execute on DeactivateClientAccount to ClientRole;
--& // not used in app
grant execute on AddToCart to ClientRole;
grant execute on RemoveFromCart to ClientRole;
--------------------------------------------------

-- роль гостя
create role GuestRole;
grant create session to GuestRole;
--&
grant execute on GetCatalog to GuestRole;
grant execute on GetItemInfo to GuestRole;
--&
grant execute on SignUpAsClient to GuestRole;
grant execute on SignIn to GuestRole;
--------------------------------------------------

-- профиль и пользователи БД
create profile UserProfile limit 
  password_life_time unlimited
  idle_time 180;
  
create user ADMIN identified by "ADMIN_PASSWORD"
  profile UserProfile
  account unlock;
grant AdminRole to ADMIN;

create user CLIENT identified by "CLIENT_PASSWORD"
  profile UserProfile
  account unlock;
grant ClientRole to CLIENT;

create user GUEST identified by "GUEST_PASSWORD"
  profile UserProfile
  account unlock;
grant GuestRole to GUEST;
--------------------------------------------------

-- администратор по умолчанию
declare id Accounts.id%type;
begin
  CreateNewAdminAccount('admin', 'admin', '?', '?', id);
  commit;
end;
--------------------------------------------------