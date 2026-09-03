-- ============================================================
-- READING GARDEN
-- MASTER DATABASE SCHEMA
-- ============================================================
--
-- IMPORTANT:
-- This script resets ONLY the Reading Garden application tables.
-- Supabase Auth users are NOT deleted.
--
-- Run this entire script once in:
-- Supabase Dashboard -> SQL Editor -> New query
--
-- ============================================================


BEGIN;


-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================================
-- CLEAN RESET OF READING GARDEN TABLES
-- ============================================================
--
-- This removes old/incompatible versions of the app tables.
-- Auth users remain untouched.
--
-- ============================================================

DROP TABLE IF EXISTS public.highlights CASCADE;
DROP TABLE IF EXISTS public.reading_sessions CASCADE;
DROP TABLE IF EXISTS public.goals CASCADE;
DROP TABLE IF EXISTS public.books CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;


-- ============================================================
-- PROFILES
-- ============================================================

CREATE TABLE public.profiles (

    id uuid
        PRIMARY KEY
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    display_name text
        NOT NULL
        DEFAULT '',

    avatar_url text
        NOT NULL
        DEFAULT '',

    created_at timestamptz
        NOT NULL
        DEFAULT now(),

    updated_at timestamptz
        NOT NULL
        DEFAULT now()

);


-- ============================================================
-- BOOKS
-- ============================================================

CREATE TABLE public.books (

    id uuid
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id uuid
        NOT NULL
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    title text
        NOT NULL,

    author text
        NOT NULL
        DEFAULT '',

    isbn text
        NOT NULL
        DEFAULT '',

    publisher text
        NOT NULL
        DEFAULT '',

    description text
        NOT NULL
        DEFAULT '',

    page_count integer
        NOT NULL
        DEFAULT 0,

    current_page integer
        NOT NULL
        DEFAULT 0,

    status text
        NOT NULL
        DEFAULT 'want',

    rating numeric(2,1)
        NOT NULL
        DEFAULT 0,

    genre text
        NOT NULL
        DEFAULT '',

    tags text[]
        NOT NULL
        DEFAULT '{}'::text[],

    cover_url text
        NOT NULL
        DEFAULT '',

    start_date date,

    finish_date date,

    -- Canonical field used by the current Reading Garden HTML.
    favorite boolean
        NOT NULL
        DEFAULT false,

    -- Compatibility field for versions that used British spelling.
    -- It is kept synchronized with "favorite" by a trigger.
    favourite boolean
        NOT NULL
        DEFAULT false,

    review text
        NOT NULL
        DEFAULT '',

    notes text
        NOT NULL
        DEFAULT '',

    created_at timestamptz
        NOT NULL
        DEFAULT now(),

    updated_at timestamptz
        NOT NULL
        DEFAULT now(),

    CONSTRAINT books_page_count_check
        CHECK (page_count >= 0),

    CONSTRAINT books_current_page_check
        CHECK (
            current_page >= 0
            AND current_page <=
                CASE
                    WHEN page_count > 0
                    THEN page_count
                    ELSE current_page
                END
        ),

    CONSTRAINT books_status_check
        CHECK (
            status IN (
                'want',
                'reading',
                'completed',
                'hold',
                'dnf'
            )
        ),

    CONSTRAINT books_rating_check
        CHECK (
            rating >= 0
            AND rating <= 5
        )

);


-- ============================================================
-- READING SESSIONS
-- ============================================================

CREATE TABLE public.reading_sessions (

    id uuid
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id uuid
        NOT NULL
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    book_id uuid
        NOT NULL
        REFERENCES public.books(id)
        ON DELETE CASCADE,

    reading_date date
        NOT NULL
        DEFAULT CURRENT_DATE,

    start_time timestamptz,

    end_time timestamptz,

    minutes integer
        NOT NULL
        DEFAULT 0,

    pages integer
        NOT NULL
        DEFAULT 0,

    notes text
        NOT NULL
        DEFAULT '',

    created_at timestamptz
        NOT NULL
        DEFAULT now(),

    CONSTRAINT reading_sessions_minutes_check
        CHECK (minutes >= 0),

    CONSTRAINT reading_sessions_pages_check
        CHECK (pages >= 0)

);


-- ============================================================
-- READING GOALS
-- ============================================================

CREATE TABLE public.goals (

    id uuid
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id uuid
        NOT NULL
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    year integer
        NOT NULL,

    books_target integer
        NOT NULL
        DEFAULT 24,

    pages_target integer
        NOT NULL
        DEFAULT 5000,

    minutes_target integer
        NOT NULL
        DEFAULT 10000,

    created_at timestamptz
        NOT NULL
        DEFAULT now(),

    updated_at timestamptz
        NOT NULL
        DEFAULT now(),

    CONSTRAINT goals_books_target_check
        CHECK (books_target > 0),

    CONSTRAINT goals_pages_target_check
        CHECK (pages_target > 0),

    CONSTRAINT goals_minutes_target_check
        CHECK (minutes_target > 0),

    CONSTRAINT goals_user_year_unique
        UNIQUE (user_id, year)

);


-- ============================================================
-- HIGHLIGHTS
-- ============================================================

CREATE TABLE public.highlights (

    id uuid
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id uuid
        NOT NULL
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    book_id uuid
        NOT NULL
        REFERENCES public.books(id)
        ON DELETE CASCADE,

    text text
        NOT NULL,

    page integer
        NOT NULL
        DEFAULT 0,

    note text
        NOT NULL
        DEFAULT '',

    color text
        NOT NULL
        DEFAULT 'yellow',

    created_at timestamptz
        NOT NULL
        DEFAULT now(),

    updated_at timestamptz
        NOT NULL
        DEFAULT now(),

    CONSTRAINT highlights_page_check
        CHECK (page >= 0),

    CONSTRAINT highlights_color_check
        CHECK (
            color IN (
                'yellow',
                'green',
                'blue',
                'pink',
                'purple'
            )
        )

);


-- ============================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    NEW.updated_at = now();

    RETURN NEW;

END;
$$;


-- ============================================================
-- FAVORITE / FAVOURITE COMPATIBILITY FUNCTION
-- ============================================================
--
-- Reading Garden currently uses "favorite".
-- Older versions may use "favourite".
--
-- If one is changed, the other follows.
--
-- ============================================================

CREATE OR REPLACE FUNCTION public.sync_book_favourite()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.favorite IS DISTINCT FROM false THEN
            NEW.favourite = NEW.favorite;
        ELSE
            NEW.favorite = COALESCE(NEW.favourite, false);
            NEW.favourite = NEW.favorite;
        END IF;

    ELSE

        IF NEW.favorite IS DISTINCT FROM OLD.favorite
           AND NEW.favourite IS NOT DISTINCT FROM OLD.favourite THEN

            NEW.favourite = NEW.favorite;

        ELSIF NEW.favourite IS DISTINCT FROM OLD.favourite
              AND NEW.favorite IS NOT DISTINCT FROM OLD.favorite THEN

            NEW.favorite = NEW.favourite;

        ELSE

            NEW.favourite = NEW.favorite;

        END IF;

    END IF;

    RETURN NEW;

END;
$$;


-- ============================================================
-- PROFILE UPDATED_AT
-- ============================================================

CREATE TRIGGER profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- BOOK UPDATED_AT
-- ============================================================

CREATE TRIGGER books_updated_at
BEFORE UPDATE ON public.books
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- BOOK FAVORITE COMPATIBILITY
-- ============================================================

CREATE TRIGGER books_favourite_sync
BEFORE INSERT OR UPDATE ON public.books
FOR EACH ROW
EXECUTE FUNCTION public.sync_book_favourite();


-- ============================================================
-- READING SESSION DOES NOT NEED updated_at
-- ============================================================


-- ============================================================
-- GOAL UPDATED_AT
-- ============================================================

CREATE TRIGGER goals_updated_at
BEFORE UPDATE ON public.goals
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- HIGHLIGHT UPDATED_AT
-- ============================================================

CREATE TRIGGER highlights_updated_at
BEFORE UPDATE ON public.highlights
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- AUTOMATIC PROFILE CREATION
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    INSERT INTO public.profiles (
        id,
        display_name
    )

    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data ->> 'display_name',
            ''
        )
    )

    ON CONFLICT (id)
    DO NOTHING;

    RETURN NEW;

END;
$$;


-- ============================================================
-- AUTH USER -> PROFILE TRIGGER
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created
ON auth.users;


CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX books_user_id_idx
ON public.books(user_id);


CREATE INDEX books_user_status_idx
ON public.books(user_id, status);


CREATE INDEX books_user_updated_idx
ON public.books(user_id, updated_at DESC);


CREATE INDEX books_user_favorite_idx
ON public.books(user_id, favorite);


CREATE INDEX reading_sessions_user_id_idx
ON public.reading_sessions(user_id);


CREATE INDEX reading_sessions_book_id_idx
ON public.reading_sessions(book_id);


CREATE INDEX reading_sessions_date_idx
ON public.reading_sessions(
    user_id,
    reading_date DESC
);


CREATE INDEX goals_user_id_idx
ON public.goals(user_id);


CREATE INDEX goals_user_year_idx
ON public.goals(user_id, year);


CREATE INDEX highlights_user_id_idx
ON public.highlights(user_id);


CREATE INDEX highlights_book_id_idx
ON public.highlights(book_id);


CREATE INDEX highlights_created_idx
ON public.highlights(
    user_id,
    created_at DESC
);


-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.profiles
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.books
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.reading_sessions
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.goals
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.highlights
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- PROFILE POLICIES
-- ============================================================

CREATE POLICY "Reading Garden profiles select own"
ON public.profiles
FOR SELECT
TO authenticated
USING (
    auth.uid() = id
);


CREATE POLICY "Reading Garden profiles insert own"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = id
);


CREATE POLICY "Reading Garden profiles update own"
ON public.profiles
FOR UPDATE
TO authenticated
USING (
    auth.uid() = id
)
WITH CHECK (
    auth.uid() = id
);


-- ============================================================
-- BOOK POLICIES
-- ============================================================

CREATE POLICY "Reading Garden books select own"
ON public.books
FOR SELECT
TO authenticated
USING (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden books insert own"
ON public.books
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden books update own"
ON public.books
FOR UPDATE
TO authenticated
USING (
    auth.uid() = user_id
)
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden books delete own"
ON public.books
FOR DELETE
TO authenticated
USING (
    auth.uid() = user_id
);


-- ============================================================
-- READING SESSION POLICIES
-- ============================================================

CREATE POLICY "Reading Garden sessions select own"
ON public.reading_sessions
FOR SELECT
TO authenticated
USING (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden sessions insert own"
ON public.reading_sessions
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden sessions update own"
ON public.reading_sessions
FOR UPDATE
TO authenticated
USING (
    auth.uid() = user_id
)
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden sessions delete own"
ON public.reading_sessions
FOR DELETE
TO authenticated
USING (
    auth.uid() = user_id
);


-- ============================================================
-- GOAL POLICIES
-- ============================================================

CREATE POLICY "Reading Garden goals select own"
ON public.goals
FOR SELECT
TO authenticated
USING (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden goals insert own"
ON public.goals
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden goals update own"
ON public.goals
FOR UPDATE
TO authenticated
USING (
    auth.uid() = user_id
)
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden goals delete own"
ON public.goals
FOR DELETE
TO authenticated
USING (
    auth.uid() = user_id
);


-- ============================================================
-- HIGHLIGHT POLICIES
-- ============================================================

CREATE POLICY "Reading Garden highlights select own"
ON public.highlights
FOR SELECT
TO authenticated
USING (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden highlights insert own"
ON public.highlights
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden highlights update own"
ON public.highlights
FOR UPDATE
TO authenticated
USING (
    auth.uid() = user_id
)
WITH CHECK (
    auth.uid() = user_id
);


CREATE POLICY "Reading Garden highlights delete own"
ON public.highlights
FOR DELETE
TO authenticated
USING (
    auth.uid() = user_id
);


-- ============================================================
-- GRANTS
-- ============================================================

GRANT USAGE
ON SCHEMA public
TO authenticated;


GRANT SELECT, INSERT, UPDATE, DELETE
ON public.profiles
TO authenticated;


GRANT SELECT, INSERT, UPDATE, DELETE
ON public.books
TO authenticated;


GRANT SELECT, INSERT, UPDATE, DELETE
ON public.reading_sessions
TO authenticated;


GRANT SELECT, INSERT, UPDATE, DELETE
ON public.goals
TO authenticated;


GRANT SELECT, INSERT, UPDATE, DELETE
ON public.highlights
TO authenticated;


-- ============================================================
-- REALTIME
-- ============================================================
--
-- Enables the tables for Supabase Realtime.
-- The current HTML primarily reloads cloud data, but this also
-- prepares the database for live cross-device updates.
--
-- ============================================================

DO $$
BEGIN

    BEGIN
        ALTER PUBLICATION supabase_realtime
        ADD TABLE public.books;
    EXCEPTION
        WHEN duplicate_object THEN
            NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime
        ADD TABLE public.reading_sessions;
    EXCEPTION
        WHEN duplicate_object THEN
            NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime
        ADD TABLE public.goals;
    EXCEPTION
        WHEN duplicate_object THEN
            NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime
        ADD TABLE public.highlights;
    EXCEPTION
        WHEN duplicate_object THEN
            NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime
        ADD TABLE public.profiles;
    EXCEPTION
        WHEN duplicate_object THEN
            NULL;
    END;

END;
$$;


-- ============================================================
-- POSTGREST SCHEMA CACHE
-- ============================================================

NOTIFY pgrst, 'reload schema';


COMMIT;


-- ============================================================
-- VERIFICATION
-- ============================================================

SELECT
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name IN (
    'profiles',
    'books',
    'reading_sessions',
    'goals',
    'highlights'
)
ORDER BY
    table_name,
    ordinal_position;