-- зарегистрироваться как клиент
create or replace procedure SignUpAsClient(
  p_login in Accounts.login%type,
  p_password in varchar2,
  p_fullname in varchar2,
  p_email in varchar2,
  p_address in varchar2,
  p_account_id out Accounts.id%type
) is
  r_exists boolean;
  r_role_id Roles.id%type;
  r_key AccountsKeys.key%type;
begin
  if AccountExists(p_login) then
    raise_application_error(-20001, 'LOGIN_ALREADY_EXISTS_EXCEPTION');
  end if;
  
  select id into r_role_id from Roles where role_name = 'CLIENTROLE';
  CreateAccount(r_role_id, p_login, p_password, p_fullname, p_email, p_account_id);
  select key into r_key from AccountsKeys where account_id = p_account_id;
  insert into Clients(account_id, address)
    values (p_account_id, EncryptAES128(p_address, r_key));
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/
-- войти
create or replace procedure SignIn(
  p_login in Accounts.login%type,
  p_password in varchar2,
  p_account_id out Accounts.id%type,
  p_role_name out Roles.role_name%type
) is
begin
  if not AccountExists(p_login, p_password) then
    raise_application_error(-20004, 'ACCOUNT_NOT_FOUND_EXCEPTION');
  end if;
  
  select id, role_name
    into p_account_id, p_role_name
    from V_AccountsWithRoles
    where login = p_login;
exception
  when others then
    raise_application_error(-20099, 'OTHER_EXCEPTION: '||SQLERRM);
end;
/