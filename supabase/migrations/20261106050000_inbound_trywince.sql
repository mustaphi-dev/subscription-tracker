-- Forwarding addresses move to the real domain; Cloudflare Email Routing catches *@trywince.app.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, inbound_parse_email)
  values (new.id, 'trials+' || replace(new.id::text, '-', '') || '@trywince.app');
  return new;
end $$;

update public.profiles
   set inbound_parse_email = 'trials+' || replace(id::text, '-', '') || '@trywince.app';
