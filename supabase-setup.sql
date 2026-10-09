-- SG HEMARI Strafenkasse – einmal im Supabase SQL-Editor ausführen.
-- VORHER: unten bei "insert into private.settings" deinen Kassenwart-PIN eintragen (mind. 6 Zeichen).

create extension if not exists pgcrypto with schema extensions;

create table public.players (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.catalog (
  id uuid primary key default gen_random_uuid(),
  nr int not null,
  title text not null,
  amount numeric(6,2) not null check (amount >= 0)
);

create table public.fines (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references public.players(id) on delete set null,
  player_name text not null,
  catalog_id uuid references public.catalog(id) on delete set null,
  title text not null,
  amount numeric(6,2) not null,
  day date not null default current_date,
  created_at timestamptz not null default now()
);

-- Jeder darf lesen, niemand direkt schreiben
alter table public.players enable row level security;
alter table public.catalog enable row level security;
alter table public.fines   enable row level security;
create policy "lesen" on public.players for select using (true);
create policy "lesen" on public.catalog for select using (true);
create policy "lesen" on public.fines   for select using (true);

-- PIN liegt in einem nicht öffentlichen Schema
create schema private;
revoke all on schema private from anon, authenticated;
create table private.settings (pin_hash text not null);
insert into private.settings (pin_hash) values (extensions.crypt('HIER-DEIN-PIN', extensions.gen_salt('bf')));

create function private.pin_ok(p text) returns boolean
language sql security definer set search_path = public, private, extensions as $$
  select exists (select 1 from private.settings where pin_hash = crypt(coalesce(p,''), pin_hash));
$$;

create function public.check_pin(p text) returns boolean
language sql security definer set search_path = public, private, extensions as $$
  select private.pin_ok(p);
$$;

create function public.add_fine(p text, pid uuid, cid uuid, d date) returns uuid
language plpgsql security definer set search_path = public, private, extensions as $$
declare pl public.players; c public.catalog; new_id uuid;
begin
  if not private.pin_ok(p) then raise exception 'Falscher PIN'; end if;
  select * into pl from public.players where id = pid;
  select * into c from public.catalog where id = cid;
  if pl.id is null or c.id is null then raise exception 'Spieler oder Vergehen nicht gefunden'; end if;
  insert into public.fines (player_id, player_name, catalog_id, title, amount, day)
  values (pl.id, pl.name, c.id, c.title, c.amount, coalesce(d, current_date)) returning id into new_id;
  return new_id;
end $$;

create function public.delete_fine(p text, fid uuid) returns void
language plpgsql security definer set search_path = public, private, extensions as $$
begin
  if not private.pin_ok(p) then raise exception 'Falscher PIN'; end if;
  delete from public.fines where id = fid;
end $$;

create function public.add_player(p text, n text) returns uuid
language plpgsql security definer set search_path = public, private, extensions as $$
declare new_id uuid;
begin
  if not private.pin_ok(p) then raise exception 'Falscher PIN'; end if;
  insert into public.players (name) values (trim(n)) returning id into new_id;
  return new_id;
end $$;

create function public.delete_player(p text, pid uuid) returns void
language plpgsql security definer set search_path = public, private, extensions as $$
begin
  if not private.pin_ok(p) then raise exception 'Falscher PIN'; end if;
  delete from public.players where id = pid;
end $$;

create function public.save_catalog(p text, cid uuid, t text, a numeric) returns uuid
language plpgsql security definer set search_path = public, private, extensions as $$
declare new_id uuid;
begin
  if not private.pin_ok(p) then raise exception 'Falscher PIN'; end if;
  if cid is null then
    insert into public.catalog (nr, title, amount)
    values ((select coalesce(max(nr),0)+1 from public.catalog), trim(t), a) returning id into new_id;
    return new_id;
  end if;
  update public.catalog set title = trim(t), amount = a where id = cid;
  return cid;
end $$;

create function public.delete_catalog(p text, cid uuid) returns void
language plpgsql security definer set search_path = public, private, extensions as $$
begin
  if not private.pin_ok(p) then raise exception 'Falscher PIN'; end if;
  delete from public.catalog where id = cid;
end $$;

revoke execute on function private.pin_ok(text) from public, anon, authenticated;
grant execute on function public.check_pin(text), public.add_fine(text,uuid,uuid,date), public.delete_fine(text,uuid),
  public.add_player(text,text), public.delete_player(text,uuid), public.save_catalog(text,uuid,text,numeric),
  public.delete_catalog(text,uuid) to anon, authenticated;

-- Live-Updates
alter publication supabase_realtime add table public.players, public.catalog, public.fines;

-- Startdaten
insert into public.catalog (nr, title, amount) values
 (1,'Mit Zusage nicht zum Training kommen',2),
 (2,'Zu spät zum Spiel ab 10 Min.',5),
 (3,'Zu spät zum Training ab 5 Min.',1),
 (4,'Gelb wegen Meckerns',3),
 (5,'Mit Zusage nicht zum Spiel kommen',15),
 (6,'Mit Zusage nicht zum Training kommen',5),
 (7,'Keine Rückmeldung zum Training / Spiel',2),
 (8,'Trinken bevor der Kasten angebrüllt ist',1),
 (9,'Trainingszubehör oder SG-Klamotten beim Spiel vergessen',2);

insert into public.players (name) values
 ('Joko S.'),('Enrico S.'),('Mirko W.'),('Levin K.'),('Marlo F.'),('Hannes W.'),('Till B.'),
 ('Mathis M.'),('Oliver U.'),('David B.'),('Henrik M.'),('Simon S.'),('Moritz S.'),('Roman F.'),
 ('Tim L.'),('Theo G.'),('Hussein A.'),('Malte H.'),('Andrej T.'),('Muhittin Ö.'),('Linus M.'),
 ('Jannick N.'),('Sahin T.'),('Jonah L.'),('Valentin M.'),('Moritz D.'),('Matze H.'),('Stefan K.');
