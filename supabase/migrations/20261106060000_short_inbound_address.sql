-- Short, personal forwarding addresses: <email name>-<5 random chars>@trywince.app, e.g. adams-k7f2x@trywince.app.
-- The random part keeps it unguessable (a known address could be used to plant fake trials).
create function public.new_inbound_address(email text) returns text
language plpgsql set search_path = '' as $$
declare
  -- First word of the mailbox name: adams.mustapha.dev@gmail.com -> adams.
  name text := left(nullif((regexp_split_to_array(lower(split_part(coalesce(email, ''), '@', 1)), '[^a-z0-9]+'))[1], ''), 15);
  addr text;
begin
  loop
    addr := coalesce(name, 'me') || '-' ||
      (select string_agg(substr('abcdefghjkmnpqrstuvwxyz23456789', 1 + floor(random() * 31)::int, 1), '') from generate_series(1, 5))
      || '@trywince.app';
    exit when not exists (select 1 from public.profiles where inbound_parse_email = addr);
  end loop;
  return addr;
end $$;
revoke execute on function public.new_inbound_address(text) from public, anon, authenticated;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, inbound_parse_email) values (new.id, public.new_inbound_address(new.email));
  return new;
end $$;

update public.profiles p
   set inbound_parse_email = public.new_inbound_address(u.email)
  from auth.users u
 where u.id = p.id;
