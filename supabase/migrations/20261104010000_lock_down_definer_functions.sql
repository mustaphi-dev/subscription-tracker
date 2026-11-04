-- Cron / trigger-only functions: not callable over the API.
revoke execute on function public.roll_forward_items() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.on_base_change() from public, anon, authenticated;
-- user_base() runs inside the items/sources trigger as the signed-in user, so authenticated keeps it.
revoke execute on function public.user_base(uuid) from public, anon;
