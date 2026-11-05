create or replace function public.sync_user_profile(
  p_user_id uuid,
  p_name text,
  p_email text,
  p_phone text
)
returns table (
  user_id uuid,
  name text,
  email text,
  phone text,
  photo_uploaded boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  insert into public.users as profile (
    user_id,
    name,
    email,
    phone
  )
  values (
    p_user_id,
    p_name,
    p_email,
    p_phone
  )
  on conflict (user_id) do update
  set name = excluded.name,
      email = excluded.email,
      phone = excluded.phone,
      updated_at = now();

  return query
  select profile.user_id,
         profile.name,
         profile.email,
         profile.phone,
         profile.photo_uploaded
  from public.users as profile
  where profile.user_id = p_user_id;
end;
$$;

revoke all on function public.sync_user_profile(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.sync_user_profile(uuid, text, text, text)
  to service_role;

notify pgrst, 'reload schema';
