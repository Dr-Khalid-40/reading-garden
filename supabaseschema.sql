-- ============================================================
-- READING GARDEN
-- Cloud Database Schema
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- PROFILES
-- ============================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text default '',
  avatar_url text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- BOOKS
-- ============================================================

create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  title text not null,
  author text default '',
  isbn text default '',
  publisher text default '',
  description text default '',

  page_count integer not null default 0
    check (page_count >= 0),

  current_page integer not null default 0
    check (current_page >= 0),

  status text not null default 'want'
    check (
      status in (
        'want',
        'reading',
        'completed',
        'hold',
        'dnf'
      )
    ),

  rating numeric(2,1) default 0
    check (rating >= 0 and rating <= 5),

  genre text default '',
  tags text[] not null default '{}',

  cover_url text default '',

  start_date date,
  finish_date date,

  favorite boolean not null default false,

  review text default '',
  notes text default '',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- READING SESSIONS
-- ============================================================

create table if not exists public.reading_sessions (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  book_id uuid not null
    references public.books(id)
    on delete cascade,

  reading_date date not null default current_date,

  start_time timestamptz,
  end_time timestamptz,

  minutes integer not null default 0
    check (minutes >= 0),

  pages integer not null default 0
    check (pages >= 0),

  notes text default '',

  created_at timestamptz not null default now()
);

-- ============================================================
-- GOALS
-- ============================================================

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  year integer not null,

  books_target integer not null default 24
    check (books_target > 0),

  pages_target integer not null default 5000
    check (pages_target > 0),

  minutes_target integer not null default 10000
    check (minutes_target > 0),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(user_id, year)
);

-- ============================================================
-- HIGHLIGHTS
-- ============================================================

create table if not exists public.highlights (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  book_id uuid not null
    references public.books(id)
    on delete cascade,

  text text not null,

  page integer default 0
    check (page >= 0),

  note text default '',

  color text not null default 'yellow'
    check (
      color in (
        'yellow',
        'green',
        'blue',
        'pink',
        'purple'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists books_user_id_idx
  on public.books(user_id);

create index if not exists books_status_idx
  on public.books(user_id, status);

create index if not exists books_updated_idx
  on public.books(user_id, updated_at desc);

create index if not exists sessions_user_id_idx
  on public.reading_sessions(user_id);

create index if not exists sessions_book_id_idx
  on public.reading_sessions(book_id);

create index if not exists sessions_date_idx
  on public.reading_sessions(user_id, reading_date desc);

create index if not exists goals_user_year_idx
  on public.goals(user_id, year);

create index if not exists highlights_book_idx
  on public.highlights(book_id);

-- ============================================================
-- UPDATED_AT FUNCTION
-- ============================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================
-- UPDATED_AT TRIGGERS
-- ============================================================

drop trigger if exists profiles_updated_at
on public.profiles;

create trigger profiles_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();


drop trigger if exists books_updated_at
on public.books;

create trigger books_updated_at
before update on public.books
for each row
execute function public.set_updated_at();


drop trigger if exists goals_updated_at
on public.goals;

create trigger goals_updated_at
before update on public.goals
for each row
execute function public.set_updated_at();


drop trigger if exists highlights_updated_at
on public.highlights;

create trigger highlights_updated_at
before update on public.highlights
for each row
execute function public.set_updated_at();

-- ============================================================
-- NEW USER PROFILE
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  insert into public.profiles (
    id,
    display_name
  )
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      split_part(coalesce(new.email, ''), '@', 1),
      ''
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created
on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;
alter table public.books enable row level security;
alter table public.reading_sessions enable row level security;
alter table public.goals enable row level security;
alter table public.highlights enable row level security;

-- ============================================================
-- PROFILE POLICIES
-- ============================================================

drop policy if exists "Users can view own profile"
on public.profiles;

create policy "Users can view own profile"
on public.profiles
for select
to authenticated
using (auth.uid() = id);


drop policy if exists "Users can insert own profile"
on public.profiles;

create policy "Users can insert own profile"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);


drop policy if exists "Users can update own profile"
on public.profiles;

create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- ============================================================
-- BOOK POLICIES
-- ============================================================

drop policy if exists "Users can view own books"
on public.books;

create policy "Users can view own books"
on public.books
for select
to authenticated
using (auth.uid() = user_id);


drop policy if exists "Users can create own books"
on public.books;

create policy "Users can create own books"
on public.books
for insert
to authenticated
with check (auth.uid() = user_id);


drop policy if exists "Users can update own books"
on public.books;

create policy "Users can update own books"
on public.books
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);


drop policy if exists "Users can delete own books"
on public.books;

create policy "Users can delete own books"
on public.books
for delete
to authenticated
using (auth.uid() = user_id);

-- ============================================================
-- SESSION POLICIES
-- ============================================================

drop policy if exists "Users can view own sessions"
on public.reading_sessions;

create policy "Users can view own sessions"
on public.reading_sessions
for select
to authenticated
using (auth.uid() = user_id);


drop policy if exists "Users can create own sessions"
on public.reading_sessions;

create policy "Users can create own sessions"
on public.reading_sessions
for insert
to authenticated
with check (auth.uid() = user_id);


drop policy if exists "Users can update own sessions"
on public.reading_sessions;

create policy "Users can update own sessions"
on public.reading_sessions
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);


drop policy if exists "Users can delete own sessions"
on public.reading_sessions;

create policy "Users can delete own sessions"
on public.reading_sessions
for delete
to authenticated
using (auth.uid() = user_id);

-- ============================================================
-- GOAL POLICIES
-- ============================================================

drop policy if exists "Users can view own goals"
on public.goals;

create policy "Users can view own goals"
on public.goals
for select
to authenticated
using (auth.uid() = user_id);


drop policy if exists "Users can create own goals"
on public.goals;

create policy "Users can create own goals"
on public.goals
for insert
to authenticated
with check (auth.uid() = user_id);


drop policy if exists "Users can update own goals"
on public.goals;

create policy "Users can update own goals"
on public.goals
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);


drop policy if exists "Users can delete own goals"
on public.goals;

create policy "Users can delete own goals"
on public.goals
for delete
to authenticated
using (auth.uid() = user_id);

-- ============================================================
-- HIGHLIGHT POLICIES
-- ============================================================

drop policy if exists "Users can view own highlights"
on public.highlights;

create policy "Users can view own highlights"
on public.highlights
for select
to authenticated
using (auth.uid() = user_id);


drop policy if exists "Users can create own highlights"
on public.highlights;

create policy "Users can create own highlights"
on public.highlights
for insert
to authenticated
with check (auth.uid() = user_id);


drop policy if exists "Users can update own highlights"
on public.highlights;

create policy "Users can update own highlights"
on public.highlights
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);


drop policy if exists "Users can delete own highlights"
on public.highlights;

create policy "Users can delete own highlights"
on public.highlights
for delete
to authenticated
using (auth.uid() = user_id);

-- ============================================================
-- GRANTS
-- ============================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete
on public.profiles
to authenticated;

grant select, insert, update, delete
on public.books
to authenticated;

grant select, insert, update, delete
on public.reading_sessions
to authenticated;

grant select, insert, update, delete
on public.goals
to authenticated;

grant select, insert, update, delete
on public.highlights
to authenticated;

-- ============================================================
-- DONE
-- ============================================================