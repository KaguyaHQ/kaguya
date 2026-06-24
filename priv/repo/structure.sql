--
-- PostgreSQL database dump
--

\restrict LFmIbLEl95wlJylgT6QdeAz0aHgUzUYOTSpM0TN64xNAdHzYuQJS5dKlT4OGAx9

-- Dumped from database version 17.8 (Homebrew)
-- Dumped by pg_dump version 17.8 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'suspended',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    action character varying(255) NOT NULL,
    target_type character varying(255) NOT NULL,
    target_id uuid,
    details text,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: banned_sf_ids; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banned_sf_ids (
    vndb_sf_id text NOT NULL,
    reason character varying(255) DEFAULT 'wd14_moderation'::character varying NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: banned_vndb_ids; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banned_vndb_ids (
    vndb_id character varying(255) NOT NULL,
    title character varying(255),
    reason character varying(255),
    banned_at timestamp(0) without time zone NOT NULL
);


--
-- Name: changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.changes (
    id uuid NOT NULL,
    entity_type character varying(255) NOT NULL,
    entity_id uuid NOT NULL,
    revision_number integer NOT NULL,
    action character varying(255) NOT NULL,
    changed_fields character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    summary text NOT NULL,
    source character varying(255) DEFAULT 'user'::character varying NOT NULL,
    user_id uuid,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: character_favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.character_favorites (
    user_id uuid NOT NULL,
    character_id uuid NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: character_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.character_images (
    id uuid NOT NULL,
    character_id uuid NOT NULL,
    width integer,
    height integer,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    uploaded_by uuid,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL
);


--
-- Name: character_images_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.character_images_hist (
    change_id uuid NOT NULL,
    image_id uuid NOT NULL,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL
);


--
-- Name: character_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.character_likes (
    user_id uuid NOT NULL,
    character_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: characters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.characters (
    id uuid NOT NULL,
    vndb_id character varying(255),
    name text NOT NULL,
    description text,
    slug character varying(255) NOT NULL,
    sex character varying(255),
    spoiler_sex character varying(255),
    gender character varying(255),
    spoiler_gender character varying(255),
    blood_type character varying(255),
    height smallint,
    weight smallint,
    age smallint,
    birthday smallint,
    bust smallint,
    waist smallint,
    hip smallint,
    cup_size character varying(255),
    vndb_image_id character varying(255),
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    primary_image_id uuid,
    temp_image_url character varying(255),
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    favorites_count integer DEFAULT 0 NOT NULL
);


--
-- Name: characters_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.characters_hist (
    change_id uuid NOT NULL,
    name text,
    description text,
    sex character varying(255),
    spoiler_sex character varying(255),
    gender character varying(255),
    spoiler_gender character varying(255),
    blood_type character varying(255),
    height smallint,
    weight smallint,
    age smallint,
    birthday smallint,
    bust smallint,
    waist smallint,
    hip smallint,
    cup_size character varying(255),
    primary_image_id uuid,
    is_image_nsfw boolean DEFAULT false,
    is_image_suggestive boolean DEFAULT false,
    slug character varying(255),
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false
);


--
-- Name: list_comment_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_comment_likes (
    user_id uuid NOT NULL,
    list_comment_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: list_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_comments (
    id uuid NOT NULL,
    list_id uuid NOT NULL,
    user_id uuid NOT NULL,
    parent_comment_id uuid,
    content text NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    is_edited boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    hidden_at timestamp(0) without time zone
);


--
-- Name: list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_items (
    visual_novel_id uuid NOT NULL,
    list_id uuid NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    tier_id uuid,
    tier_position integer,
    CONSTRAINT list_items_tier_position_positive_check CHECK (((tier_position IS NULL) OR (tier_position > 0)))
);


--
-- Name: list_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_likes (
    user_id uuid NOT NULL,
    list_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: list_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_tiers (
    id uuid NOT NULL,
    list_id uuid NOT NULL,
    label character varying(255) NOT NULL,
    color character varying(255) NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT list_tiers_position_positive_check CHECK (("position" > 0))
);


--
-- Name: lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lists (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    description text,
    is_public boolean DEFAULT true NOT NULL,
    is_ranked boolean DEFAULT false NOT NULL,
    vns_count integer DEFAULT 0 NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    comments_count integer DEFAULT 0 NOT NULL,
    trending_score double precision DEFAULT 0.0 NOT NULL,
    last_activity_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    hidden_at timestamp(0) without time zone,
    display_mode character varying(255) DEFAULT 'grid'::character varying NOT NULL,
    CONSTRAINT lists_display_mode_check CHECK (((display_mode)::text = ANY (ARRAY[('grid'::character varying)::text, ('tier'::character varying)::text])))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    action character varying(255) NOT NULL,
    entity_type character varying(255) NOT NULL,
    entity_id uuid,
    read boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    idempotency_key character varying(255)
);


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '14';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: post_comment_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_comment_likes (
    post_comment_id uuid NOT NULL,
    user_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: post_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_comments (
    id uuid NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    parent_comment_id uuid,
    content text NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    is_edited boolean DEFAULT false NOT NULL,
    hidden_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deleted_at timestamp(0) without time zone,
    deleted_by_type character varying(255),
    hidden_reason text,
    hidden_mod_note text,
    is_pinned boolean DEFAULT false NOT NULL,
    pinned_at timestamp without time zone,
    short_id character varying(16) NOT NULL
);


--
-- Name: post_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_likes (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    last_comment_user_id uuid,
    title character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    content text,
    category_type character varying(255) DEFAULT 'general'::character varying NOT NULL,
    entity_id uuid,
    comments_count integer DEFAULT 0 NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    last_comment_at timestamp(0) without time zone,
    is_pinned boolean DEFAULT false NOT NULL,
    is_locked boolean DEFAULT false NOT NULL,
    is_edited boolean DEFAULT false NOT NULL,
    hidden_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deleted_at timestamp(0) without time zone,
    deleted_by_type character varying(255),
    short_id character varying(8) NOT NULL,
    hidden_reason text,
    hidden_mod_note text
);


--
-- Name: producer_external_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producer_external_links (
    producer_id uuid NOT NULL,
    site character varying(255) NOT NULL,
    value text NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: producer_external_links_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producer_external_links_hist (
    change_id uuid NOT NULL,
    site character varying(255) NOT NULL,
    value text NOT NULL
);


--
-- Name: producer_follows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producer_follows (
    follower_id uuid NOT NULL,
    producer_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: producer_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producer_images (
    id uuid NOT NULL,
    producer_id uuid NOT NULL,
    uploaded_by uuid,
    width integer,
    height integer,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: producers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producers (
    id uuid NOT NULL,
    vndb_id character varying(255),
    name character varying(255) NOT NULL,
    description text,
    producer_type character varying(255),
    language character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    slug character varying(255),
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL,
    follower_count integer DEFAULT 0 NOT NULL,
    primary_image_id uuid,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL
);


--
-- Name: producers_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producers_hist (
    change_id uuid NOT NULL,
    name character varying(255),
    description text,
    producer_type character varying(255),
    language character varying(255),
    slug character varying(255),
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false,
    primary_image_id uuid,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL
);


--
-- Name: quote_favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quote_favorites (
    user_id uuid NOT NULL,
    vn_quote_id uuid NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: ratings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ratings (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    rating real NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    source character varying(255)
);


--
-- Name: reading_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reading_statuses (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    status character varying(255) NOT NULL,
    date_started date,
    date_finished date,
    library_added_at timestamp(0) without time zone NOT NULL,
    note text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    source character varying(255),
    CONSTRAINT status_check CHECK (((status)::text = ANY (ARRAY[('read'::character varying)::text, ('did_not_finish'::character varying)::text, ('on_hold'::character varying)::text, ('want_to_read'::character varying)::text, ('currently_reading'::character varying)::text, ('not_interested'::character varying)::text])))
);


--
-- Name: release_extlinks_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.release_extlinks_hist (
    change_id uuid NOT NULL,
    site character varying(255) NOT NULL,
    label character varying(255),
    url text NOT NULL
);


--
-- Name: releases_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.releases_hist (
    change_id uuid NOT NULL,
    title text,
    display_title text,
    latin_title text,
    original_language character varying(255),
    release_date date,
    release_type character varying(255),
    patch boolean DEFAULT false,
    freeware boolean DEFAULT false,
    official boolean DEFAULT true,
    has_ero boolean DEFAULT false,
    uncensored boolean,
    voiced smallint,
    minage smallint,
    engine character varying(255),
    platforms character varying(255)[] DEFAULT ARRAY[]::character varying[],
    languages character varying(255)[] DEFAULT ARRAY[]::character varying[],
    mtl_languages character varying(255)[] DEFAULT ARRAY[]::character varying[],
    producers jsonb DEFAULT '[]'::jsonb,
    notes text,
    reso_x smallint,
    reso_y smallint,
    media jsonb DEFAULT '[]'::jsonb,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid NOT NULL,
    status character varying(255) DEFAULT 'new'::character varying NOT NULL,
    category character varying(255) DEFAULT 'other'::character varying NOT NULL,
    entity_type character varying(255) NOT NULL,
    entity_id uuid,
    entity_name text,
    reason text NOT NULL,
    message text,
    reporter_id uuid NOT NULL,
    resolved_by uuid,
    resolved_at timestamp(0) without time zone,
    mod_notes text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    resolution_note text
);


--
-- Name: review_comment_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.review_comment_likes (
    user_id uuid NOT NULL,
    review_comment_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: review_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.review_comments (
    id uuid NOT NULL,
    review_id uuid NOT NULL,
    user_id uuid NOT NULL,
    parent_comment_id uuid,
    content text NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    is_edited boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    hidden_at timestamp(0) without time zone
);


--
-- Name: review_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.review_likes (
    user_id uuid NOT NULL,
    review_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    user_id uuid NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    trending_score double precision DEFAULT 0.0 NOT NULL,
    comments_count integer DEFAULT 0 NOT NULL,
    is_edited boolean DEFAULT false NOT NULL,
    is_spoiler boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    source character varying(255),
    content text NOT NULL,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL
);


--
-- Name: saved_browse_filters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_browse_filters (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    sort_by character varying(50),
    is_default boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: shelf_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shelf_items (
    shelf_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: shelves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shelves (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    vns_count integer DEFAULT 0 NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: site_stat_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site_stat_snapshots (
    date date NOT NULL,
    ratings_count integer DEFAULT 0 NOT NULL,
    reading_statuses_count integer DEFAULT 0 NOT NULL,
    reviews_count integer DEFAULT 0 NOT NULL,
    users_count integer DEFAULT 0 NOT NULL,
    dau_count integer DEFAULT 0 NOT NULL,
    vns_count integer DEFAULT 0 NOT NULL,
    characters_count integer DEFAULT 0 NOT NULL,
    producers_count integer DEFAULT 0 NOT NULL,
    releases_count integer DEFAULT 0 NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    mau_30d_count integer DEFAULT 0 NOT NULL
);


--
-- Name: slug_redirects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slug_redirects (
    id uuid NOT NULL,
    entity_type character varying(255) NOT NULL,
    old_slug character varying(255) NOT NULL,
    target_id uuid NOT NULL,
    scope_id uuid,
    reason character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: tag_parents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tag_parents (
    tag_id uuid NOT NULL,
    parent_tag_id uuid NOT NULL,
    is_main boolean DEFAULT false NOT NULL
);


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    description text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    source character varying(255),
    vndb_tag_id character varying(255),
    category smallint,
    default_spoiler_level smallint DEFAULT 0,
    is_theme boolean DEFAULT false NOT NULL,
    kind smallint,
    content_warning boolean DEFAULT false NOT NULL,
    CONSTRAINT tags_source_check CHECK (((source IS NULL) OR ((source)::text = ANY ((ARRAY['manual'::character varying, 'vndb'::character varying, 'other'::character varying])::text[]))))
);


--
-- Name: user_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_activities (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    action character varying(255) NOT NULL,
    entity_type character varying(255) NOT NULL,
    entity_id uuid NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: user_follows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_follows (
    follower_id uuid NOT NULL,
    followed_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT cannot_follow_self CHECK ((follower_id <> followed_id))
);


--
-- Name: user_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_identities (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    provider character varying(255) NOT NULL,
    provider_uid character varying(255) NOT NULL,
    email character varying(255),
    email_verified boolean DEFAULT false NOT NULL,
    name character varying(255),
    avatar_url text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: user_library_exports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_library_exports (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    status character varying(255) DEFAULT 'queued'::character varying NOT NULL,
    object_key text,
    row_count integer DEFAULT 0 NOT NULL,
    byte_size integer,
    error text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT user_library_exports_status_check CHECK (((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('processing'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: user_period_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_period_stats (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    period integer,
    read_time_minutes integer DEFAULT 0 NOT NULL,
    producers_count integer DEFAULT 0 NOT NULL,
    vns_hist jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_time_hist jsonb DEFAULT '{}'::jsonb NOT NULL,
    most_read_vn_tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    highest_rated_vn_tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    most_read_producers jsonb DEFAULT '[]'::jsonb NOT NULL,
    highest_rated_producers jsonb DEFAULT '[]'::jsonb NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    mean_score_hist jsonb DEFAULT '{}'::jsonb NOT NULL,
    vns_by_release_year_hist jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_time_by_release_year_hist jsonb DEFAULT '{}'::jsonb NOT NULL,
    mean_score_by_release_year_hist jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: user_recommendation_feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_recommendation_feedback (
    user_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    signal integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT signal_check CHECK ((signal = ANY (ARRAY['-1'::integer, 1])))
);


--
-- Name: user_recommendations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_recommendations (
    user_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    score double precision NOT NULL,
    ease_score double precision NOT NULL,
    rank integer NOT NULL,
    model_version character varying(255) NOT NULL,
    generated_at timestamp without time zone NOT NULL,
    reasons jsonb DEFAULT '[]'::jsonb NOT NULL,
    total_positive_contribution double precision
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    username public.citext,
    email public.citext NOT NULL,
    display_name character varying(100),
    avatar_id uuid,
    banner_id uuid,
    bio text,
    social_links jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    role character varying DEFAULT 'user'::character varying NOT NULL,
    favorite_visual_novels uuid[] DEFAULT ARRAY[]::uuid[],
    ratings_dist integer[] DEFAULT ARRAY[0, 0, 0, 0, 0, 0, 0, 0, 0, 0] NOT NULL,
    ratings_count integer DEFAULT 0 NOT NULL,
    average_rating real DEFAULT 0.0 NOT NULL,
    reviews_count integer DEFAULT 0 NOT NULL,
    show_nsfw_images boolean DEFAULT false NOT NULL,
    favorite_characters uuid[] DEFAULT ARRAY[]::uuid[],
    show_nukige boolean DEFAULT false NOT NULL,
    show_adjacent boolean DEFAULT true NOT NULL,
    ratings_suppressed boolean DEFAULT false NOT NULL,
    edit_count integer DEFAULT 0 NOT NULL,
    can_edit boolean DEFAULT true NOT NULL,
    can_discuss boolean DEFAULT true NOT NULL,
    can_review boolean DEFAULT true NOT NULL,
    can_list boolean DEFAULT true NOT NULL,
    mod_db boolean DEFAULT false NOT NULL,
    mod_discussions boolean DEFAULT false NOT NULL,
    mod_reviews boolean DEFAULT false NOT NULL,
    mod_lists boolean DEFAULT false NOT NULL,
    mod_users boolean DEFAULT false NOT NULL,
    show_nsfw_screenshots boolean DEFAULT false NOT NULL,
    show_brutal_screenshots boolean DEFAULT false NOT NULL
);


--
-- Name: users_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255),
    authenticated_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: visual_novels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.visual_novels (
    id uuid NOT NULL,
    title text NOT NULL,
    description text,
    slug character varying(255) NOT NULL,
    vndb_id character varying(255),
    development_status character varying(255),
    length_category character varying(255),
    length_minutes integer,
    original_language character varying(255),
    release_date date,
    min_age integer,
    average_rating real DEFAULT 3.5 NOT NULL,
    ratings_count integer DEFAULT 0 NOT NULL,
    ratings_dist integer[] DEFAULT ARRAY[0, 0, 0, 0, 0, 0, 0, 0, 0, 0] NOT NULL,
    reviews_count integer DEFAULT 0 NOT NULL,
    vndb_rating numeric(4,2),
    vndb_vote_count integer DEFAULT 0 NOT NULL,
    temp_image_url character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    primary_image_id uuid,
    has_ero boolean DEFAULT false NOT NULL,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL,
    primary_vn_series_id uuid,
    primary_series_position double precision,
    featured_screenshot_id uuid,
    aliases text[] DEFAULT ARRAY[]::text[] NOT NULL,
    title_category character varying(255) DEFAULT 'vn'::character varying NOT NULL,
    is_cover_pinned boolean DEFAULT false NOT NULL,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL,
    is_avn boolean DEFAULT false NOT NULL,
    content_score smallint DEFAULT 0 NOT NULL,
    content_score_breakdown jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_score_updated_at timestamp(0) without time zone,
    CONSTRAINT development_status_check CHECK (((development_status IS NULL) OR ((development_status)::text = ANY (ARRAY[('finished'::character varying)::text, ('in_development'::character varying)::text, ('on_hiatus'::character varying)::text, ('abandoned'::character varying)::text])))),
    CONSTRAINT length_category_check CHECK (((length_category IS NULL) OR ((length_category)::text = ANY (ARRAY[('short'::character varying)::text, ('medium'::character varying)::text, ('long'::character varying)::text, ('very_long'::character varying)::text])))),
    CONSTRAINT min_age_check CHECK (((min_age IS NULL) OR (min_age >= 0)))
);


--
-- Name: vn_characters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_characters (
    visual_novel_id uuid NOT NULL,
    character_id uuid NOT NULL,
    role character varying(255) NOT NULL,
    spoiler_level smallint DEFAULT 0 NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_characters_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_characters_hist (
    change_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    role character varying(255) NOT NULL,
    spoiler_level smallint DEFAULT 0,
    character_id uuid
);


--
-- Name: vn_covers_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_covers_hist (
    change_id uuid NOT NULL,
    cover_id uuid NOT NULL,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL,
    language character varying(255),
    release_date date,
    width integer,
    height integer
);


--
-- Name: vn_engines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_engines (
    visual_novel_id uuid NOT NULL,
    engine character varying(255) NOT NULL
);


--
-- Name: vn_external_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_external_links (
    vn_id uuid NOT NULL,
    site character varying(255) NOT NULL,
    value text NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_external_links_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_external_links_hist (
    change_id uuid NOT NULL,
    site character varying(255) NOT NULL,
    value text NOT NULL
);


--
-- Name: vn_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_hist (
    change_id uuid NOT NULL,
    title text,
    description text,
    aliases text[] DEFAULT ARRAY[]::text[],
    development_status character varying(255),
    length_category character varying(255),
    original_language character varying(255),
    release_date date,
    min_age integer,
    has_ero boolean DEFAULT false,
    title_category character varying(255) DEFAULT 'vn'::character varying,
    primary_image_id uuid,
    is_image_nsfw boolean DEFAULT false,
    is_image_suggestive boolean DEFAULT false,
    slug character varying(255),
    length_minutes integer,
    primary_vn_series_id uuid,
    primary_series_position double precision,
    featured_screenshot_id uuid,
    is_cover_pinned boolean DEFAULT false,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false,
    is_avn boolean DEFAULT false NOT NULL
);


--
-- Name: vn_image_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_image_likes (
    user_id uuid NOT NULL,
    vn_image_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_images (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    width integer,
    height integer,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    vndb_cv_id text,
    likes_count integer DEFAULT 0 NOT NULL,
    is_image_nsfw boolean DEFAULT false NOT NULL,
    is_image_suggestive boolean DEFAULT false NOT NULL,
    vndb_votes integer DEFAULT 0 NOT NULL,
    language character varying(255),
    release_date date,
    uploaded_by uuid
);


--
-- Name: vn_languages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_languages (
    visual_novel_id uuid NOT NULL,
    language character varying(255) NOT NULL
);


--
-- Name: vn_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_merges (
    merged_id uuid NOT NULL,
    canonical_id uuid NOT NULL,
    merged_slug character varying(255) NOT NULL,
    merged_title text,
    merged_vndb_id character varying(255),
    merged_by_user_id uuid,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_platforms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_platforms (
    visual_novel_id uuid NOT NULL,
    platform character varying(255) NOT NULL
);


--
-- Name: vn_producers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_producers (
    visual_novel_id uuid NOT NULL,
    producer_id uuid NOT NULL,
    role character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    earliest_release_date date
);


--
-- Name: vn_quote_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_quote_likes (
    user_id uuid NOT NULL,
    vn_quote_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_quotes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_quotes (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    character_id uuid,
    quote text NOT NULL,
    score integer DEFAULT 0 NOT NULL,
    vndb_id text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    created_by uuid,
    favorites_count integer DEFAULT 0 NOT NULL
);


--
-- Name: vn_relations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_relations (
    visual_novel_id uuid NOT NULL,
    related_vn_id uuid NOT NULL,
    relation_type character varying(255) NOT NULL,
    is_official boolean DEFAULT true NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT relation_type_check CHECK (((relation_type)::text = ANY (ARRAY[('sequel'::character varying)::text, ('prequel'::character varying)::text, ('fandisc'::character varying)::text, ('original'::character varying)::text, ('side_story'::character varying)::text, ('parent_story'::character varying)::text, ('same_setting'::character varying)::text, ('alternative'::character varying)::text, ('shares_characters'::character varying)::text, ('same_series'::character varying)::text])))
);


--
-- Name: vn_relations_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_relations_hist (
    change_id uuid NOT NULL,
    related_vn_id uuid NOT NULL,
    relation_type character varying(255) NOT NULL,
    is_official boolean DEFAULT true
);


--
-- Name: vn_release_extlinks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_release_extlinks (
    id uuid NOT NULL,
    vn_release_id uuid NOT NULL,
    site character varying(255) NOT NULL,
    label character varying(255),
    url text NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_releases (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    vndb_id character varying(255),
    title text NOT NULL,
    latin_title text,
    original_language character varying(255),
    release_date date,
    release_type character varying(255),
    patch boolean DEFAULT false,
    freeware boolean DEFAULT false,
    official boolean DEFAULT true,
    has_ero boolean DEFAULT false,
    uncensored boolean,
    voiced smallint,
    minage smallint,
    engine character varying(255),
    platforms character varying(255)[] DEFAULT ARRAY[]::character varying[],
    languages character varying(255)[] DEFAULT ARRAY[]::character varying[],
    mtl_languages character varying(255)[] DEFAULT ARRAY[]::character varying[],
    producers jsonb DEFAULT '[]'::jsonb,
    notes text,
    reso_x smallint,
    reso_y smallint,
    media jsonb DEFAULT '[]'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    display_title text,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL
);


--
-- Name: vn_screenshot_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_screenshot_likes (
    user_id uuid NOT NULL,
    vn_screenshot_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_screenshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_screenshots (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    vndb_sf_id text,
    width integer,
    height integer,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    likes_count integer DEFAULT 0 NOT NULL,
    is_nsfw boolean DEFAULT false NOT NULL,
    release_id uuid,
    uploaded_by uuid,
    s3_key text,
    is_brutal boolean DEFAULT false NOT NULL
);


--
-- Name: vn_screenshots_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_screenshots_hist (
    change_id uuid NOT NULL,
    screenshot_id uuid NOT NULL,
    is_nsfw boolean DEFAULT false NOT NULL,
    release_id uuid,
    width integer,
    height integer,
    is_brutal boolean DEFAULT false NOT NULL
);


--
-- Name: vn_series; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_series (
    id uuid NOT NULL,
    name text NOT NULL,
    slug character varying(255) NOT NULL,
    description text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL,
    source character varying(255) DEFAULT 'vndb_sync'::character varying NOT NULL,
    manual_fields character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    imported_root_visual_novel_id uuid,
    CONSTRAINT vn_series_manual_fields_check CHECK (((manual_fields)::text[] <@ ARRAY['general'::text, 'entries'::text, 'producers'::text])),
    CONSTRAINT vn_series_source_check CHECK (((source)::text = ANY (ARRAY[('user'::character varying)::text, ('vndb_sync'::character varying)::text])))
);


--
-- Name: vn_series_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_series_hist (
    change_id uuid NOT NULL,
    name text,
    slug text,
    description text,
    hidden_at timestamp(0) without time zone,
    is_locked boolean DEFAULT false NOT NULL,
    source character varying(255) NOT NULL,
    manual_fields character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    imported_root_visual_novel_id uuid
);


--
-- Name: vn_series_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_series_items (
    visual_novel_id uuid NOT NULL,
    vn_series_id uuid NOT NULL,
    "position" double precision NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vn_series_items_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_series_items_hist (
    change_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    "position" double precision NOT NULL
);


--
-- Name: vn_series_producers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_series_producers (
    vn_series_id uuid NOT NULL,
    producer_id uuid NOT NULL,
    role character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT vn_series_producers_role_check CHECK (((role)::text = ANY (ARRAY[('developer'::character varying)::text, ('publisher'::character varying)::text, ('developer_publisher'::character varying)::text])))
);


--
-- Name: vn_series_producers_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_series_producers_hist (
    change_id uuid NOT NULL,
    producer_id uuid NOT NULL,
    role character varying(255) NOT NULL
);


--
-- Name: vn_similarities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_similarities (
    visual_novel_id uuid NOT NULL,
    similar_vn_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    upvotes_count integer DEFAULT 0 NOT NULL,
    downvotes_count integer DEFAULT 0 NOT NULL,
    score double precision DEFAULT 0.0 NOT NULL,
    CONSTRAINT different_vns CHECK ((visual_novel_id <> similar_vn_id)),
    CONSTRAINT visual_novel_id_lt_similar_vn_id CHECK ((visual_novel_id < similar_vn_id))
);


--
-- Name: vn_similarity_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_similarity_votes (
    user_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    similar_vn_id uuid NOT NULL,
    vote_value integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT vote_value_must_be_minus_1_or_1 CHECK ((vote_value = ANY (ARRAY['-1'::integer, 1])))
);


--
-- Name: vn_tag_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_tag_votes (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    spoiler_level integer DEFAULT 0,
    inserted_at timestamp(0) without time zone NOT NULL,
    value smallint NOT NULL,
    CONSTRAINT vn_tag_votes_value_check CHECK (((value >= 0) AND (value <= 5)))
);


--
-- Name: vn_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_tags (
    visual_novel_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    vndb_vote_count integer DEFAULT 0 NOT NULL,
    vndb_avg_score double precision,
    relevance_score double precision DEFAULT 0.0 NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    spoiler_level smallint,
    is_overruled boolean DEFAULT false NOT NULL,
    overruled_by uuid
);


--
-- Name: vn_titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_titles (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    lang text NOT NULL,
    official boolean DEFAULT true NOT NULL,
    title text NOT NULL,
    latin text
);


--
-- Name: vn_titles_hist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_titles_hist (
    change_id uuid NOT NULL,
    lang text NOT NULL,
    title text NOT NULL,
    latin text,
    official boolean DEFAULT true
);


--
-- Name: vn_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vn_versions (
    id uuid NOT NULL,
    visual_novel_id uuid NOT NULL,
    source character varying(255) NOT NULL,
    source_id text,
    source_url text,
    version_number text NOT NULL,
    release_date timestamp(0) without time zone,
    release_type character varying(255),
    update_type character varying(255),
    changelog text,
    renders_count integer,
    animations_count integer,
    sfx_count integer,
    music_tracks_count integer,
    status character varying(255) DEFAULT 'published'::character varying NOT NULL,
    reviewed_by_user_id uuid,
    reviewed_at timestamp(0) without time zone,
    review_notes text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: vndb_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vndb_imports (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    result jsonb,
    error_message character varying(255)
);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: banned_sf_ids banned_sf_ids_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_sf_ids
    ADD CONSTRAINT banned_sf_ids_pkey PRIMARY KEY (vndb_sf_id);


--
-- Name: banned_vndb_ids banned_vndb_ids_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_vndb_ids
    ADD CONSTRAINT banned_vndb_ids_pkey PRIMARY KEY (vndb_id);


--
-- Name: changes changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_pkey PRIMARY KEY (id);


--
-- Name: character_favorites character_favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_favorites
    ADD CONSTRAINT character_favorites_pkey PRIMARY KEY (user_id, character_id);


--
-- Name: character_images character_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_images
    ADD CONSTRAINT character_images_pkey PRIMARY KEY (id);


--
-- Name: character_likes character_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_likes
    ADD CONSTRAINT character_likes_pkey PRIMARY KEY (user_id, character_id);


--
-- Name: characters_hist characters_hist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters_hist
    ADD CONSTRAINT characters_hist_pkey PRIMARY KEY (change_id);


--
-- Name: characters characters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT characters_pkey PRIMARY KEY (id);


--
-- Name: post_comments discussion_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT discussion_comments_pkey PRIMARY KEY (id);


--
-- Name: posts discussion_threads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT discussion_threads_pkey PRIMARY KEY (id);


--
-- Name: list_tiers list_tiers_list_id_position_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_tiers
    ADD CONSTRAINT list_tiers_list_id_position_unique UNIQUE (list_id, "position") DEFERRABLE;


--
-- Name: list_tiers list_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_tiers
    ADD CONSTRAINT list_tiers_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: producer_external_links producer_external_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_external_links
    ADD CONSTRAINT producer_external_links_pkey PRIMARY KEY (producer_id, site);


--
-- Name: producer_follows producer_follows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_follows
    ADD CONSTRAINT producer_follows_pkey PRIMARY KEY (follower_id, producer_id);


--
-- Name: producer_images producer_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_images
    ADD CONSTRAINT producer_images_pkey PRIMARY KEY (id);


--
-- Name: producers_hist producers_hist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producers_hist
    ADD CONSTRAINT producers_hist_pkey PRIMARY KEY (change_id);


--
-- Name: producers producers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producers
    ADD CONSTRAINT producers_pkey PRIMARY KEY (id);


--
-- Name: quote_favorites quote_favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_favorites
    ADD CONSTRAINT quote_favorites_pkey PRIMARY KEY (user_id, vn_quote_id);


--
-- Name: releases_hist releases_hist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases_hist
    ADD CONSTRAINT releases_hist_pkey PRIMARY KEY (change_id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: site_stat_snapshots site_stat_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_stat_snapshots
    ADD CONSTRAINT site_stat_snapshots_pkey PRIMARY KEY (date);


--
-- Name: slug_redirects slug_redirects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slug_redirects
    ADD CONSTRAINT slug_redirects_pkey PRIMARY KEY (id);


--
-- Name: tag_parents tag_parents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tag_parents
    ADD CONSTRAINT tag_parents_pkey PRIMARY KEY (tag_id, parent_tag_id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: user_activities user_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_activities
    ADD CONSTRAINT user_activities_pkey PRIMARY KEY (id);


--
-- Name: user_follows user_follows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_follows
    ADD CONSTRAINT user_follows_pkey PRIMARY KEY (follower_id, followed_id);


--
-- Name: user_identities user_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_identities
    ADD CONSTRAINT user_identities_pkey PRIMARY KEY (id);


--
-- Name: user_library_exports user_library_exports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_library_exports
    ADD CONSTRAINT user_library_exports_pkey PRIMARY KEY (id);


--
-- Name: user_recommendation_feedback user_vn_rec_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_recommendation_feedback
    ADD CONSTRAINT user_vn_rec_feedback_pkey PRIMARY KEY (user_id, visual_novel_id);


--
-- Name: user_recommendations user_vn_recommendations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_recommendations
    ADD CONSTRAINT user_vn_recommendations_pkey PRIMARY KEY (user_id, visual_novel_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_tokens users_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id);


--
-- Name: visual_novels visual_novels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visual_novels
    ADD CONSTRAINT visual_novels_pkey PRIMARY KEY (id);


--
-- Name: vn_characters vn_characters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_characters
    ADD CONSTRAINT vn_characters_pkey PRIMARY KEY (visual_novel_id, character_id);


--
-- Name: vn_engines vn_engines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_engines
    ADD CONSTRAINT vn_engines_pkey PRIMARY KEY (visual_novel_id, engine);


--
-- Name: vn_external_links vn_external_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_external_links
    ADD CONSTRAINT vn_external_links_pkey PRIMARY KEY (vn_id, site);


--
-- Name: vn_hist vn_hist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_hist
    ADD CONSTRAINT vn_hist_pkey PRIMARY KEY (change_id);


--
-- Name: vn_image_likes vn_image_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_image_likes
    ADD CONSTRAINT vn_image_likes_pkey PRIMARY KEY (user_id, vn_image_id);


--
-- Name: vn_images vn_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_images
    ADD CONSTRAINT vn_images_pkey PRIMARY KEY (id);


--
-- Name: vn_languages vn_languages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_languages
    ADD CONSTRAINT vn_languages_pkey PRIMARY KEY (visual_novel_id, language);


--
-- Name: list_comment_likes vn_list_comment_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comment_likes
    ADD CONSTRAINT vn_list_comment_likes_pkey PRIMARY KEY (user_id, list_comment_id);


--
-- Name: list_comments vn_list_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comments
    ADD CONSTRAINT vn_list_comments_pkey PRIMARY KEY (id);


--
-- Name: list_items vn_list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT vn_list_items_pkey PRIMARY KEY (visual_novel_id, list_id);


--
-- Name: list_likes vn_list_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_likes
    ADD CONSTRAINT vn_list_likes_pkey PRIMARY KEY (user_id, list_id);


--
-- Name: lists vn_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT vn_lists_pkey PRIMARY KEY (id);


--
-- Name: vn_merges vn_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_merges
    ADD CONSTRAINT vn_merges_pkey PRIMARY KEY (merged_id);


--
-- Name: vn_platforms vn_platforms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_platforms
    ADD CONSTRAINT vn_platforms_pkey PRIMARY KEY (visual_novel_id, platform);


--
-- Name: vn_producers vn_producers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_producers
    ADD CONSTRAINT vn_producers_pkey PRIMARY KEY (visual_novel_id, producer_id);


--
-- Name: vn_quote_likes vn_quote_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quote_likes
    ADD CONSTRAINT vn_quote_likes_pkey PRIMARY KEY (user_id, vn_quote_id);


--
-- Name: vn_quotes vn_quotes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quotes
    ADD CONSTRAINT vn_quotes_pkey PRIMARY KEY (id);


--
-- Name: ratings vn_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ratings
    ADD CONSTRAINT vn_ratings_pkey PRIMARY KEY (id);


--
-- Name: reading_statuses vn_reading_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reading_statuses
    ADD CONSTRAINT vn_reading_statuses_pkey PRIMARY KEY (id);


--
-- Name: vn_relations vn_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_relations
    ADD CONSTRAINT vn_relations_pkey PRIMARY KEY (visual_novel_id, related_vn_id);


--
-- Name: vn_release_extlinks vn_release_extlinks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_release_extlinks
    ADD CONSTRAINT vn_release_extlinks_pkey PRIMARY KEY (id);


--
-- Name: vn_releases vn_releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_releases
    ADD CONSTRAINT vn_releases_pkey PRIMARY KEY (id);


--
-- Name: review_comment_likes vn_review_comment_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comment_likes
    ADD CONSTRAINT vn_review_comment_likes_pkey PRIMARY KEY (user_id, review_comment_id);


--
-- Name: review_comments vn_review_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comments
    ADD CONSTRAINT vn_review_comments_pkey PRIMARY KEY (id);


--
-- Name: review_likes vn_review_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_likes
    ADD CONSTRAINT vn_review_likes_pkey PRIMARY KEY (user_id, review_id);


--
-- Name: reviews vn_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT vn_reviews_pkey PRIMARY KEY (id);


--
-- Name: saved_browse_filters vn_saved_browse_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_browse_filters
    ADD CONSTRAINT vn_saved_browse_filters_pkey PRIMARY KEY (id);


--
-- Name: vn_screenshot_likes vn_screenshot_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshot_likes
    ADD CONSTRAINT vn_screenshot_likes_pkey PRIMARY KEY (user_id, vn_screenshot_id);


--
-- Name: vn_screenshots vn_screenshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshots
    ADD CONSTRAINT vn_screenshots_pkey PRIMARY KEY (id);


--
-- Name: vn_series_hist vn_series_hist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_hist
    ADD CONSTRAINT vn_series_hist_pkey PRIMARY KEY (change_id);


--
-- Name: vn_series_items vn_series_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_items
    ADD CONSTRAINT vn_series_items_pkey PRIMARY KEY (visual_novel_id, vn_series_id);


--
-- Name: vn_series vn_series_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series
    ADD CONSTRAINT vn_series_pkey PRIMARY KEY (id);


--
-- Name: vn_series_producers vn_series_producers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_producers
    ADD CONSTRAINT vn_series_producers_pkey PRIMARY KEY (vn_series_id, producer_id);


--
-- Name: shelf_items vn_shelf_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shelf_items
    ADD CONSTRAINT vn_shelf_items_pkey PRIMARY KEY (shelf_id, visual_novel_id);


--
-- Name: shelves vn_shelves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shelves
    ADD CONSTRAINT vn_shelves_pkey PRIMARY KEY (id);


--
-- Name: vn_similarities vn_similarities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarities
    ADD CONSTRAINT vn_similarities_pkey PRIMARY KEY (visual_novel_id, similar_vn_id);


--
-- Name: vn_similarity_votes vn_similarity_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarity_votes
    ADD CONSTRAINT vn_similarity_votes_pkey PRIMARY KEY (user_id, visual_novel_id, similar_vn_id);


--
-- Name: vn_tag_votes vn_tag_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tag_votes
    ADD CONSTRAINT vn_tag_votes_pkey PRIMARY KEY (id);


--
-- Name: vn_tags vn_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tags
    ADD CONSTRAINT vn_tags_pkey PRIMARY KEY (visual_novel_id, tag_id);


--
-- Name: vn_titles vn_titles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_titles
    ADD CONSTRAINT vn_titles_pkey PRIMARY KEY (id);


--
-- Name: user_period_stats vn_user_period_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_period_stats
    ADD CONSTRAINT vn_user_period_stats_pkey PRIMARY KEY (id);


--
-- Name: vn_versions vn_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_versions
    ADD CONSTRAINT vn_versions_pkey PRIMARY KEY (id);


--
-- Name: vndb_imports vndb_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vndb_imports
    ADD CONSTRAINT vndb_imports_pkey PRIMARY KEY (id);


--
-- Name: audit_log_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_inserted_at_index ON public.audit_log USING btree (inserted_at);


--
-- Name: audit_log_target_type_target_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_target_type_target_id_index ON public.audit_log USING btree (target_type, target_id);


--
-- Name: audit_log_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_user_id_index ON public.audit_log USING btree (user_id);


--
-- Name: changes_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX changes_entity_type_entity_id_index ON public.changes USING btree (entity_type, entity_id);


--
-- Name: changes_entity_type_entity_id_revision_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX changes_entity_type_entity_id_revision_number_index ON public.changes USING btree (entity_type, entity_id, revision_number);


--
-- Name: changes_entity_type_inserted_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX changes_entity_type_inserted_at_idx ON public.changes USING btree (entity_type, inserted_at DESC);


--
-- Name: changes_source_inserted_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX changes_source_inserted_at_idx ON public.changes USING btree (source, inserted_at DESC);


--
-- Name: changes_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX changes_user_id_index ON public.changes USING btree (user_id);


--
-- Name: character_favorites_character_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX character_favorites_character_id_inserted_at_index ON public.character_favorites USING btree (character_id, inserted_at);


--
-- Name: character_favorites_user_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX character_favorites_user_id_position_index ON public.character_favorites USING btree (user_id, "position");


--
-- Name: character_images_character_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX character_images_character_id_index ON public.character_images USING btree (character_id);


--
-- Name: character_images_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX character_images_hist_change_id_index ON public.character_images_hist USING btree (change_id);


--
-- Name: character_likes_character_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX character_likes_character_id_index ON public.character_likes USING btree (character_id);


--
-- Name: characters_browse_popular_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX characters_browse_popular_index ON public.characters USING btree (favorites_count DESC, id) WHERE (hidden_at IS NULL);


--
-- Name: characters_favorites_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX characters_favorites_count_index ON public.characters USING btree (favorites_count);


--
-- Name: characters_likes_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX characters_likes_count_index ON public.characters USING btree (likes_count);


--
-- Name: characters_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX characters_slug_index ON public.characters USING btree (slug);


--
-- Name: characters_updated_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX characters_updated_at_id_index ON public.characters USING btree (updated_at, id) WHERE ((hidden_at IS NULL) AND (slug IS NOT NULL));


--
-- Name: characters_vndb_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX characters_vndb_id_index ON public.characters USING btree (vndb_id);


--
-- Name: discussion_comments_discussion_thread_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_comments_discussion_thread_id_index ON public.post_comments USING btree (post_id);


--
-- Name: discussion_comments_parent_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_comments_parent_comment_id_index ON public.post_comments USING btree (parent_comment_id);


--
-- Name: discussion_comments_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_comments_user_id_index ON public.post_comments USING btree (user_id);


--
-- Name: discussion_threads_inserted_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_threads_inserted_at_id_index ON public.posts USING btree (inserted_at, id);


--
-- Name: discussion_threads_last_comment_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_threads_last_comment_at_id_index ON public.posts USING btree (last_comment_at, id);


--
-- Name: discussion_threads_likes_count_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_threads_likes_count_id_index ON public.posts USING btree (likes_count, id);


--
-- Name: discussion_threads_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discussion_threads_user_id_index ON public.posts USING btree (user_id);


--
-- Name: idx_vns_neg_ratings_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vns_neg_ratings_id ON public.visual_novels USING btree (((- ratings_count)), id);


--
-- Name: list_comments_list_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX list_comments_list_id_index ON public.list_comments USING btree (list_id);


--
-- Name: list_comments_parent_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX list_comments_parent_comment_id_index ON public.list_comments USING btree (parent_comment_id);


--
-- Name: list_items_list_id_tier_id_tier_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX list_items_list_id_tier_id_tier_position_index ON public.list_items USING btree (list_id, tier_id, tier_position);


--
-- Name: list_items_list_id_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX list_items_list_id_visual_novel_id_index ON public.list_items USING btree (list_id, visual_novel_id);


--
-- Name: list_likes_list_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX list_likes_list_id_inserted_at_index ON public.list_likes USING btree (list_id, inserted_at);


--
-- Name: lists_last_activity_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lists_last_activity_at_id_index ON public.lists USING btree (last_activity_at, id);


--
-- Name: lists_likes_count_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lists_likes_count_id_index ON public.lists USING btree (likes_count, id);


--
-- Name: lists_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX lists_slug_index ON public.lists USING btree (slug);


--
-- Name: lists_updated_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lists_updated_at_id_index ON public.lists USING btree (updated_at, id) WHERE ((is_public = true) AND (hidden_at IS NULL));


--
-- Name: lists_user_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX lists_user_id_name_index ON public.lists USING btree (user_id, name);


--
-- Name: lists_user_id_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX lists_user_id_slug_index ON public.lists USING btree (user_id, slug);


--
-- Name: notifications_user_action_idempotency_key_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notifications_user_action_idempotency_key_index ON public.notifications USING btree (user_id, action, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: notifications_user_id_read_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_user_id_read_inserted_at_index ON public.notifications USING btree (user_id, read, inserted_at);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_cancelled_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_cancelled_at_index ON public.oban_jobs USING btree (state, cancelled_at);


--
-- Name: oban_jobs_state_discarded_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_discarded_at_index ON public.oban_jobs USING btree (state, discarded_at);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: post_comment_likes_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_comment_likes_pkey ON public.post_comment_likes USING btree (post_comment_id, user_id);


--
-- Name: post_comments_post_parent_likes_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_comments_post_parent_likes_id_index ON public.post_comments USING btree (post_id, likes_count, id) WHERE (parent_comment_id IS NULL);


--
-- Name: post_comments_short_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_comments_short_id_index ON public.post_comments USING btree (short_id) WHERE (short_id IS NOT NULL);


--
-- Name: post_likes_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_likes_pkey ON public.post_likes USING btree (post_id, user_id);


--
-- Name: posts_category_type_entity_id_last_comment_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_category_type_entity_id_last_comment_at_id_index ON public.posts USING btree (category_type, entity_id, last_comment_at, id);


--
-- Name: posts_category_type_is_pinned_last_comment_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_category_type_is_pinned_last_comment_at_index ON public.posts USING btree (category_type, is_pinned, last_comment_at);


--
-- Name: posts_category_type_last_comment_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_category_type_last_comment_at_id_index ON public.posts USING btree (category_type, last_comment_at, id);


--
-- Name: posts_short_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_short_id_index ON public.posts USING btree (short_id);


--
-- Name: posts_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_slug_index ON public.posts USING btree (slug);


--
-- Name: posts_updated_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_updated_at_id_index ON public.posts USING btree (updated_at, id) WHERE ((hidden_at IS NULL) AND (deleted_at IS NULL));


--
-- Name: producer_external_links_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producer_external_links_hist_change_id_index ON public.producer_external_links_hist USING btree (change_id);


--
-- Name: producer_follows_follower_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producer_follows_follower_id_inserted_at_index ON public.producer_follows USING btree (follower_id, inserted_at);


--
-- Name: producer_follows_producer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producer_follows_producer_id_index ON public.producer_follows USING btree (producer_id);


--
-- Name: producer_images_producer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producer_images_producer_id_index ON public.producer_images USING btree (producer_id);


--
-- Name: producers_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producers_name_index ON public.producers USING btree (name);


--
-- Name: producers_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX producers_slug_index ON public.producers USING btree (slug);


--
-- Name: producers_updated_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producers_updated_at_id_index ON public.producers USING btree (updated_at, id) WHERE ((hidden_at IS NULL) AND (slug IS NOT NULL));


--
-- Name: producers_vndb_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX producers_vndb_id_index ON public.producers USING btree (vndb_id);


--
-- Name: quote_favorites_user_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX quote_favorites_user_id_position_index ON public.quote_favorites USING btree (user_id, "position");


--
-- Name: quote_favorites_vn_quote_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX quote_favorites_vn_quote_id_inserted_at_index ON public.quote_favorites USING btree (vn_quote_id, inserted_at);


--
-- Name: ratings_user_id_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ratings_user_id_visual_novel_id_index ON public.ratings USING btree (user_id, visual_novel_id);


--
-- Name: ratings_visual_novel_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ratings_visual_novel_id_inserted_at_index ON public.ratings USING btree (visual_novel_id, inserted_at);


--
-- Name: reading_statuses_user_id_status_date_finished_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reading_statuses_user_id_status_date_finished_index ON public.reading_statuses USING btree (user_id, status, date_finished);


--
-- Name: reading_statuses_user_id_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reading_statuses_user_id_visual_novel_id_index ON public.reading_statuses USING btree (user_id, visual_novel_id);


--
-- Name: reading_statuses_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reading_statuses_visual_novel_id_index ON public.reading_statuses USING btree (visual_novel_id);


--
-- Name: release_extlinks_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX release_extlinks_hist_change_id_index ON public.release_extlinks_hist USING btree (change_id);


--
-- Name: reports_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_entity_type_entity_id_index ON public.reports USING btree (entity_type, entity_id);


--
-- Name: reports_no_duplicate_open; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reports_no_duplicate_open ON public.reports USING btree (reporter_id, entity_type, entity_id) WHERE ((status)::text = ANY (ARRAY[('new'::character varying)::text, ('in_progress'::character varying)::text]));


--
-- Name: reports_reporter_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_reporter_id_index ON public.reports USING btree (reporter_id);


--
-- Name: reports_status_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_status_inserted_at_index ON public.reports USING btree (status, inserted_at);


--
-- Name: review_comments_parent_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX review_comments_parent_comment_id_index ON public.review_comments USING btree (parent_comment_id);


--
-- Name: review_comments_review_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX review_comments_review_id_index ON public.review_comments USING btree (review_id);


--
-- Name: reviews_trending_score_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reviews_trending_score_index ON public.reviews USING btree (trending_score);


--
-- Name: reviews_updated_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reviews_updated_at_id_index ON public.reviews USING btree (updated_at, id) WHERE (hidden_at IS NULL);


--
-- Name: reviews_user_id_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reviews_user_id_visual_novel_id_index ON public.reviews USING btree (user_id, visual_novel_id);


--
-- Name: reviews_visual_novel_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reviews_visual_novel_id_inserted_at_index ON public.reviews USING btree (visual_novel_id, inserted_at);


--
-- Name: reviews_visual_novel_id_likes_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reviews_visual_novel_id_likes_count_index ON public.reviews USING btree (visual_novel_id, likes_count);


--
-- Name: saved_browse_filters_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX saved_browse_filters_user_id_index ON public.saved_browse_filters USING btree (user_id);


--
-- Name: saved_browse_filters_user_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX saved_browse_filters_user_id_name_index ON public.saved_browse_filters USING btree (user_id, name);


--
-- Name: shelves_user_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shelves_user_id_name_index ON public.shelves USING btree (user_id, name);


--
-- Name: shelves_user_id_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shelves_user_id_slug_index ON public.shelves USING btree (user_id, slug);


--
-- Name: slug_redirects_entity_type_scope_id_old_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX slug_redirects_entity_type_scope_id_old_slug_index ON public.slug_redirects USING btree (entity_type, scope_id, old_slug) NULLS NOT DISTINCT;


--
-- Name: slug_redirects_entity_type_target_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX slug_redirects_entity_type_target_id_index ON public.slug_redirects USING btree (entity_type, target_id);


--
-- Name: slug_redirects_scope_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX slug_redirects_scope_id_index ON public.slug_redirects USING btree (scope_id) WHERE (scope_id IS NOT NULL);


--
-- Name: tag_parents_parent_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tag_parents_parent_tag_id_index ON public.tag_parents USING btree (parent_tag_id);


--
-- Name: tags_category_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tags_category_index ON public.tags USING btree (category);


--
-- Name: tags_content_warning_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tags_content_warning_index ON public.tags USING btree (content_warning) WHERE (content_warning = true);


--
-- Name: tags_kind_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tags_kind_index ON public.tags USING btree (kind);


--
-- Name: tags_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tags_slug_index ON public.tags USING btree (slug);


--
-- Name: tags_source_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tags_source_index ON public.tags USING btree (source);


--
-- Name: tags_vndb_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tags_vndb_tag_id_index ON public.tags USING btree (vndb_tag_id) WHERE (vndb_tag_id IS NOT NULL);


--
-- Name: user_activities_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_activities_entity_type_entity_id_index ON public.user_activities USING btree (entity_type, entity_id);


--
-- Name: user_activities_inserted_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_activities_inserted_at_id_index ON public.user_activities USING btree (inserted_at, id);


--
-- Name: user_activities_user_id_action_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_activities_user_id_action_entity_type_entity_id_index ON public.user_activities USING btree (user_id, action, entity_type, entity_id);


--
-- Name: user_activities_user_id_inserted_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_activities_user_id_inserted_at_id_index ON public.user_activities USING btree (user_id, inserted_at, id);


--
-- Name: user_follows_followed_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_follows_followed_id_index ON public.user_follows USING btree (followed_id);


--
-- Name: user_identities_provider_provider_uid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_identities_provider_provider_uid_index ON public.user_identities USING btree (provider, provider_uid);


--
-- Name: user_identities_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_identities_user_id_index ON public.user_identities USING btree (user_id);


--
-- Name: user_identities_user_id_provider_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_identities_user_id_provider_index ON public.user_identities USING btree (user_id, provider);


--
-- Name: user_library_exports_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_library_exports_inserted_at_index ON public.user_library_exports USING btree (inserted_at);


--
-- Name: user_library_exports_one_active_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_library_exports_one_active_per_user ON public.user_library_exports USING btree (user_id) WHERE ((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('processing'::character varying)::text]));


--
-- Name: user_library_exports_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_library_exports_user_id_index ON public.user_library_exports USING btree (user_id);


--
-- Name: user_period_stats_user_id_period_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_period_stats_user_id_period_index ON public.user_period_stats USING btree (user_id, period) NULLS NOT DISTINCT;


--
-- Name: user_recommendations_user_id_rank_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_recommendations_user_id_rank_index ON public.user_recommendations USING btree (user_id, rank);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);


--
-- Name: users_ratings_suppressed_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_ratings_suppressed_index ON public.users USING btree (id) WHERE ratings_suppressed;


--
-- Name: users_tokens_context_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token);


--
-- Name: users_tokens_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id);


--
-- Name: users_username_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_username_index ON public.users USING btree (username);


--
-- Name: visual_novels_average_rating_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_average_rating_index ON public.visual_novels USING btree (average_rating);


--
-- Name: visual_novels_content_score_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_content_score_index ON public.visual_novels USING btree (content_score) WHERE ((content_score > 0) AND (content_score < 100));


--
-- Name: visual_novels_has_ero_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_has_ero_index ON public.visual_novels USING btree (has_ero);


--
-- Name: visual_novels_is_avn_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_is_avn_index ON public.visual_novels USING btree (is_avn) WHERE (is_avn = true);


--
-- Name: visual_novels_is_image_nsfw_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_is_image_nsfw_index ON public.visual_novels USING btree (is_image_nsfw);


--
-- Name: visual_novels_is_image_suggestive_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_is_image_suggestive_index ON public.visual_novels USING btree (is_image_suggestive);


--
-- Name: visual_novels_ratings_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_ratings_count_index ON public.visual_novels USING btree (ratings_count);


--
-- Name: visual_novels_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX visual_novels_slug_index ON public.visual_novels USING btree (slug);


--
-- Name: visual_novels_title_category_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_title_category_index ON public.visual_novels USING btree (title_category);


--
-- Name: visual_novels_updated_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visual_novels_updated_at_id_index ON public.visual_novels USING btree (updated_at, id) WHERE ((hidden_at IS NULL) AND (slug IS NOT NULL));


--
-- Name: visual_novels_vndb_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX visual_novels_vndb_id_index ON public.visual_novels USING btree (vndb_id);


--
-- Name: vn_characters_character_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_characters_character_id_index ON public.vn_characters USING btree (character_id);


--
-- Name: vn_characters_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_characters_hist_change_id_index ON public.vn_characters_hist USING btree (change_id);


--
-- Name: vn_covers_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_covers_hist_change_id_index ON public.vn_covers_hist USING btree (change_id);


--
-- Name: vn_engines_engine_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_engines_engine_index ON public.vn_engines USING btree (engine);


--
-- Name: vn_external_links_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_external_links_hist_change_id_index ON public.vn_external_links_hist USING btree (change_id);


--
-- Name: vn_image_likes_vn_image_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_image_likes_vn_image_id_index ON public.vn_image_likes USING btree (vn_image_id);


--
-- Name: vn_images_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_images_visual_novel_id_index ON public.vn_images USING btree (visual_novel_id);


--
-- Name: vn_images_visual_novel_id_vndb_cv_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_images_visual_novel_id_vndb_cv_id_index ON public.vn_images USING btree (visual_novel_id, vndb_cv_id);


--
-- Name: vn_languages_language_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_languages_language_index ON public.vn_languages USING btree (language);


--
-- Name: vn_merges_canonical_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_merges_canonical_id_index ON public.vn_merges USING btree (canonical_id);


--
-- Name: vn_merges_merged_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_merges_merged_slug_index ON public.vn_merges USING btree (merged_slug);


--
-- Name: vn_merges_merged_vndb_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_merges_merged_vndb_id_index ON public.vn_merges USING btree (merged_vndb_id) WHERE (merged_vndb_id IS NOT NULL);


--
-- Name: vn_platforms_platform_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_platforms_platform_index ON public.vn_platforms USING btree (platform);


--
-- Name: vn_producers_producer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_producers_producer_id_index ON public.vn_producers USING btree (producer_id);


--
-- Name: vn_quotes_character_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_quotes_character_id_index ON public.vn_quotes USING btree (character_id);


--
-- Name: vn_quotes_favorites_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_quotes_favorites_count_index ON public.vn_quotes USING btree (favorites_count);


--
-- Name: vn_quotes_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_quotes_visual_novel_id_index ON public.vn_quotes USING btree (visual_novel_id);


--
-- Name: vn_quotes_vndb_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_quotes_vndb_id_index ON public.vn_quotes USING btree (vndb_id);


--
-- Name: vn_relations_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_relations_hist_change_id_index ON public.vn_relations_hist USING btree (change_id);


--
-- Name: vn_relations_related_vn_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_relations_related_vn_id_index ON public.vn_relations USING btree (related_vn_id);


--
-- Name: vn_release_extlinks_site_vn_release_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_release_extlinks_site_vn_release_id_index ON public.vn_release_extlinks USING btree (site, vn_release_id);


--
-- Name: vn_release_extlinks_vn_release_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_release_extlinks_vn_release_id_index ON public.vn_release_extlinks USING btree (vn_release_id);


--
-- Name: vn_release_extlinks_vn_release_id_site_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_release_extlinks_vn_release_id_site_url_index ON public.vn_release_extlinks USING btree (vn_release_id, site, url);


--
-- Name: vn_releases_freeware_vn_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_releases_freeware_vn_idx ON public.vn_releases USING btree (visual_novel_id) WHERE ((freeware = true) AND (hidden_at IS NULL));


--
-- Name: vn_releases_languages_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_releases_languages_index ON public.vn_releases USING gin (languages);


--
-- Name: vn_releases_platforms_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_releases_platforms_index ON public.vn_releases USING gin (platforms);


--
-- Name: vn_releases_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_releases_visual_novel_id_index ON public.vn_releases USING btree (visual_novel_id);


--
-- Name: vn_releases_vndb_id_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_releases_vndb_id_visual_novel_id_index ON public.vn_releases USING btree (vndb_id, visual_novel_id);


--
-- Name: vn_screenshot_likes_vn_screenshot_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_screenshot_likes_vn_screenshot_id_index ON public.vn_screenshot_likes USING btree (vn_screenshot_id);


--
-- Name: vn_screenshots_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_screenshots_hist_change_id_index ON public.vn_screenshots_hist USING btree (change_id);


--
-- Name: vn_screenshots_release_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_screenshots_release_id_index ON public.vn_screenshots USING btree (release_id);


--
-- Name: vn_screenshots_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_screenshots_visual_novel_id_index ON public.vn_screenshots USING btree (visual_novel_id);


--
-- Name: vn_screenshots_vndb_sf_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_screenshots_vndb_sf_id_index ON public.vn_screenshots USING btree (vndb_sf_id);


--
-- Name: vn_series_items_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_series_items_hist_change_id_index ON public.vn_series_items_hist USING btree (change_id);


--
-- Name: vn_series_items_vn_series_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_series_items_vn_series_id_position_index ON public.vn_series_items USING btree (vn_series_id, "position");


--
-- Name: vn_series_producers_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_series_producers_hist_change_id_index ON public.vn_series_producers_hist USING btree (change_id);


--
-- Name: vn_series_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_series_slug_index ON public.vn_series USING btree (slug);


--
-- Name: vn_series_source_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_series_source_index ON public.vn_series USING btree (source);


--
-- Name: vn_similarities_similar_vn_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_similarities_similar_vn_id_index ON public.vn_similarities USING btree (similar_vn_id);


--
-- Name: vn_tag_votes_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_tag_votes_user_id_index ON public.vn_tag_votes USING btree (user_id);


--
-- Name: vn_tag_votes_user_id_visual_novel_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_tag_votes_user_id_visual_novel_id_tag_id_index ON public.vn_tag_votes USING btree (user_id, visual_novel_id, tag_id);


--
-- Name: vn_tag_votes_visual_novel_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_tag_votes_visual_novel_id_tag_id_index ON public.vn_tag_votes USING btree (visual_novel_id, tag_id);


--
-- Name: vn_tags_tag_id_relevance_score_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_tags_tag_id_relevance_score_visual_novel_id_index ON public.vn_tags USING btree (tag_id, relevance_score, visual_novel_id);


--
-- Name: vn_tags_tag_id_visual_novel_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_tags_tag_id_visual_novel_id_index ON public.vn_tags USING btree (tag_id, visual_novel_id);


--
-- Name: vn_tags_visual_novel_id_relevance_score_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_tags_visual_novel_id_relevance_score_index ON public.vn_tags USING btree (visual_novel_id, relevance_score);


--
-- Name: vn_titles_hist_change_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_titles_hist_change_id_index ON public.vn_titles_hist USING btree (change_id);


--
-- Name: vn_titles_visual_novel_id_lang_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_titles_visual_novel_id_lang_index ON public.vn_titles USING btree (visual_novel_id, lang);


--
-- Name: vn_versions_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_versions_pending_idx ON public.vn_versions USING btree (inserted_at) WHERE ((status)::text = 'pending'::text);


--
-- Name: vn_versions_source_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vn_versions_source_id_idx ON public.vn_versions USING btree (source, source_id) WHERE (source_id IS NOT NULL);


--
-- Name: vn_versions_vn_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vn_versions_vn_id_date_idx ON public.vn_versions USING btree (visual_novel_id, release_date DESC NULLS LAST) WHERE ((status)::text = 'published'::text);


--
-- Name: vndb_imports_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vndb_imports_user_id_index ON public.vndb_imports USING btree (user_id);


--
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: changes changes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.changes
    ADD CONSTRAINT changes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: character_favorites character_favorites_character_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_favorites
    ADD CONSTRAINT character_favorites_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;


--
-- Name: character_favorites character_favorites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_favorites
    ADD CONSTRAINT character_favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: character_images character_images_character_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_images
    ADD CONSTRAINT character_images_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;


--
-- Name: character_images_hist character_images_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_images_hist
    ADD CONSTRAINT character_images_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: character_images character_images_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_images
    ADD CONSTRAINT character_images_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: character_likes character_likes_character_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_likes
    ADD CONSTRAINT character_likes_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;


--
-- Name: character_likes character_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_likes
    ADD CONSTRAINT character_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: characters_hist characters_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters_hist
    ADD CONSTRAINT characters_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: characters characters_primary_image_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT characters_primary_image_id_fkey FOREIGN KEY (primary_image_id) REFERENCES public.character_images(id) ON DELETE SET NULL;


--
-- Name: post_comment_likes discussion_comment_likes_discussion_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comment_likes
    ADD CONSTRAINT discussion_comment_likes_discussion_comment_id_fkey FOREIGN KEY (post_comment_id) REFERENCES public.post_comments(id) ON DELETE CASCADE;


--
-- Name: post_comment_likes discussion_comment_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comment_likes
    ADD CONSTRAINT discussion_comment_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: post_comments discussion_comments_discussion_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT discussion_comments_discussion_thread_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: post_comments discussion_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT discussion_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.post_comments(id) ON DELETE CASCADE;


--
-- Name: post_comments discussion_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT discussion_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: post_likes discussion_thread_likes_discussion_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT discussion_thread_likes_discussion_thread_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: post_likes discussion_thread_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT discussion_thread_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: posts discussion_threads_last_comment_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT discussion_threads_last_comment_user_id_fkey FOREIGN KEY (last_comment_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: posts discussion_threads_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT discussion_threads_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: list_comment_likes list_comment_likes_list_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comment_likes
    ADD CONSTRAINT list_comment_likes_list_comment_id_fkey FOREIGN KEY (list_comment_id) REFERENCES public.list_comments(id) ON DELETE CASCADE;


--
-- Name: list_comment_likes list_comment_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comment_likes
    ADD CONSTRAINT list_comment_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: list_comments list_comments_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comments
    ADD CONSTRAINT list_comments_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_comments list_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comments
    ADD CONSTRAINT list_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.list_comments(id) ON DELETE CASCADE;


--
-- Name: list_comments list_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_comments
    ADD CONSTRAINT list_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: list_items list_items_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_items list_items_tier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_tier_id_fkey FOREIGN KEY (tier_id) REFERENCES public.list_tiers(id) ON DELETE SET NULL;


--
-- Name: list_items list_items_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: list_likes list_likes_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_likes
    ADD CONSTRAINT list_likes_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_likes list_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_likes
    ADD CONSTRAINT list_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: list_tiers list_tiers_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_tiers
    ADD CONSTRAINT list_tiers_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: lists lists_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT lists_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: producer_external_links_hist producer_external_links_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_external_links_hist
    ADD CONSTRAINT producer_external_links_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: producer_external_links producer_external_links_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_external_links
    ADD CONSTRAINT producer_external_links_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE CASCADE;


--
-- Name: producer_follows producer_follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_follows
    ADD CONSTRAINT producer_follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: producer_follows producer_follows_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_follows
    ADD CONSTRAINT producer_follows_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE CASCADE;


--
-- Name: producer_images producer_images_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_images
    ADD CONSTRAINT producer_images_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE CASCADE;


--
-- Name: producer_images producer_images_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producer_images
    ADD CONSTRAINT producer_images_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: producers_hist producers_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producers_hist
    ADD CONSTRAINT producers_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: producers producers_primary_image_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producers
    ADD CONSTRAINT producers_primary_image_id_fkey FOREIGN KEY (primary_image_id) REFERENCES public.producer_images(id) ON DELETE SET NULL;


--
-- Name: quote_favorites quote_favorites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_favorites
    ADD CONSTRAINT quote_favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: quote_favorites quote_favorites_vn_quote_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_favorites
    ADD CONSTRAINT quote_favorites_vn_quote_id_fkey FOREIGN KEY (vn_quote_id) REFERENCES public.vn_quotes(id) ON DELETE CASCADE;


--
-- Name: ratings ratings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ratings
    ADD CONSTRAINT ratings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ratings ratings_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ratings
    ADD CONSTRAINT ratings_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: reading_statuses reading_statuses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reading_statuses
    ADD CONSTRAINT reading_statuses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reading_statuses reading_statuses_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reading_statuses
    ADD CONSTRAINT reading_statuses_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: release_extlinks_hist release_extlinks_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_extlinks_hist
    ADD CONSTRAINT release_extlinks_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: releases_hist releases_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases_hist
    ADD CONSTRAINT releases_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: reports reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: reports reports_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: review_comment_likes review_comment_likes_review_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comment_likes
    ADD CONSTRAINT review_comment_likes_review_comment_id_fkey FOREIGN KEY (review_comment_id) REFERENCES public.review_comments(id) ON DELETE CASCADE;


--
-- Name: review_comment_likes review_comment_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comment_likes
    ADD CONSTRAINT review_comment_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: review_comments review_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comments
    ADD CONSTRAINT review_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.review_comments(id) ON DELETE CASCADE;


--
-- Name: review_comments review_comments_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comments
    ADD CONSTRAINT review_comments_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.reviews(id) ON DELETE CASCADE;


--
-- Name: review_comments review_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_comments
    ADD CONSTRAINT review_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: review_likes review_likes_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_likes
    ADD CONSTRAINT review_likes_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.reviews(id) ON DELETE CASCADE;


--
-- Name: review_likes review_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_likes
    ADD CONSTRAINT review_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: saved_browse_filters saved_browse_filters_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_browse_filters
    ADD CONSTRAINT saved_browse_filters_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: shelf_items shelf_items_shelf_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shelf_items
    ADD CONSTRAINT shelf_items_shelf_id_fkey FOREIGN KEY (shelf_id) REFERENCES public.shelves(id) ON DELETE CASCADE;


--
-- Name: shelf_items shelf_items_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shelf_items
    ADD CONSTRAINT shelf_items_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: shelves shelves_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shelves
    ADD CONSTRAINT shelves_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tag_parents tag_parents_parent_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tag_parents
    ADD CONSTRAINT tag_parents_parent_tag_id_fkey FOREIGN KEY (parent_tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: tag_parents tag_parents_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tag_parents
    ADD CONSTRAINT tag_parents_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: user_activities user_activities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_activities
    ADD CONSTRAINT user_activities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_follows user_follows_followed_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_follows
    ADD CONSTRAINT user_follows_followed_id_fkey FOREIGN KEY (followed_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_follows user_follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_follows
    ADD CONSTRAINT user_follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_identities user_identities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_identities
    ADD CONSTRAINT user_identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_library_exports user_library_exports_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_library_exports
    ADD CONSTRAINT user_library_exports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_period_stats user_period_stats_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_period_stats
    ADD CONSTRAINT user_period_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_recommendation_feedback user_recommendation_feedback_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_recommendation_feedback
    ADD CONSTRAINT user_recommendation_feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_recommendation_feedback user_recommendation_feedback_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_recommendation_feedback
    ADD CONSTRAINT user_recommendation_feedback_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: user_recommendations user_recommendations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_recommendations
    ADD CONSTRAINT user_recommendations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_recommendations user_recommendations_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_recommendations
    ADD CONSTRAINT user_recommendations_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: users_tokens users_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: visual_novels visual_novels_featured_screenshot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visual_novels
    ADD CONSTRAINT visual_novels_featured_screenshot_id_fkey FOREIGN KEY (featured_screenshot_id) REFERENCES public.vn_screenshots(id) ON DELETE SET NULL;


--
-- Name: visual_novels visual_novels_primary_image_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visual_novels
    ADD CONSTRAINT visual_novels_primary_image_id_fkey FOREIGN KEY (primary_image_id) REFERENCES public.vn_images(id);


--
-- Name: visual_novels visual_novels_primary_vn_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visual_novels
    ADD CONSTRAINT visual_novels_primary_vn_series_id_fkey FOREIGN KEY (primary_vn_series_id) REFERENCES public.vn_series(id) ON DELETE SET NULL;


--
-- Name: vn_characters vn_characters_character_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_characters
    ADD CONSTRAINT vn_characters_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;


--
-- Name: vn_characters_hist vn_characters_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_characters_hist
    ADD CONSTRAINT vn_characters_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_characters vn_characters_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_characters
    ADD CONSTRAINT vn_characters_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_covers_hist vn_covers_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_covers_hist
    ADD CONSTRAINT vn_covers_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_engines vn_engines_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_engines
    ADD CONSTRAINT vn_engines_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_external_links_hist vn_external_links_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_external_links_hist
    ADD CONSTRAINT vn_external_links_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_external_links vn_external_links_vn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_external_links
    ADD CONSTRAINT vn_external_links_vn_id_fkey FOREIGN KEY (vn_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_hist vn_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_hist
    ADD CONSTRAINT vn_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_image_likes vn_image_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_image_likes
    ADD CONSTRAINT vn_image_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vn_image_likes vn_image_likes_vn_image_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_image_likes
    ADD CONSTRAINT vn_image_likes_vn_image_id_fkey FOREIGN KEY (vn_image_id) REFERENCES public.vn_images(id) ON DELETE CASCADE;


--
-- Name: vn_images vn_images_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_images
    ADD CONSTRAINT vn_images_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vn_images vn_images_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_images
    ADD CONSTRAINT vn_images_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_languages vn_languages_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_languages
    ADD CONSTRAINT vn_languages_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_merges vn_merges_canonical_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_merges
    ADD CONSTRAINT vn_merges_canonical_id_fkey FOREIGN KEY (canonical_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_merges vn_merges_merged_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_merges
    ADD CONSTRAINT vn_merges_merged_by_user_id_fkey FOREIGN KEY (merged_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vn_platforms vn_platforms_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_platforms
    ADD CONSTRAINT vn_platforms_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_producers vn_producers_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_producers
    ADD CONSTRAINT vn_producers_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE CASCADE;


--
-- Name: vn_producers vn_producers_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_producers
    ADD CONSTRAINT vn_producers_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_quote_likes vn_quote_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quote_likes
    ADD CONSTRAINT vn_quote_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vn_quote_likes vn_quote_likes_vn_quote_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quote_likes
    ADD CONSTRAINT vn_quote_likes_vn_quote_id_fkey FOREIGN KEY (vn_quote_id) REFERENCES public.vn_quotes(id) ON DELETE CASCADE;


--
-- Name: vn_quotes vn_quotes_character_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quotes
    ADD CONSTRAINT vn_quotes_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;


--
-- Name: vn_quotes vn_quotes_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quotes
    ADD CONSTRAINT vn_quotes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vn_quotes vn_quotes_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_quotes
    ADD CONSTRAINT vn_quotes_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_relations_hist vn_relations_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_relations_hist
    ADD CONSTRAINT vn_relations_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_relations vn_relations_related_vn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_relations
    ADD CONSTRAINT vn_relations_related_vn_id_fkey FOREIGN KEY (related_vn_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_relations vn_relations_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_relations
    ADD CONSTRAINT vn_relations_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_release_extlinks vn_release_extlinks_vn_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_release_extlinks
    ADD CONSTRAINT vn_release_extlinks_vn_release_id_fkey FOREIGN KEY (vn_release_id) REFERENCES public.vn_releases(id) ON DELETE CASCADE;


--
-- Name: vn_releases vn_releases_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_releases
    ADD CONSTRAINT vn_releases_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_screenshot_likes vn_screenshot_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshot_likes
    ADD CONSTRAINT vn_screenshot_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vn_screenshot_likes vn_screenshot_likes_vn_screenshot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshot_likes
    ADD CONSTRAINT vn_screenshot_likes_vn_screenshot_id_fkey FOREIGN KEY (vn_screenshot_id) REFERENCES public.vn_screenshots(id) ON DELETE CASCADE;


--
-- Name: vn_screenshots_hist vn_screenshots_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshots_hist
    ADD CONSTRAINT vn_screenshots_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_screenshots vn_screenshots_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshots
    ADD CONSTRAINT vn_screenshots_release_id_fkey FOREIGN KEY (release_id) REFERENCES public.vn_releases(id) ON DELETE SET NULL;


--
-- Name: vn_screenshots vn_screenshots_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshots
    ADD CONSTRAINT vn_screenshots_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vn_screenshots vn_screenshots_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_screenshots
    ADD CONSTRAINT vn_screenshots_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_series_hist vn_series_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_hist
    ADD CONSTRAINT vn_series_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_series_hist vn_series_hist_imported_root_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_hist
    ADD CONSTRAINT vn_series_hist_imported_root_visual_novel_id_fkey FOREIGN KEY (imported_root_visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE SET NULL;


--
-- Name: vn_series vn_series_imported_root_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series
    ADD CONSTRAINT vn_series_imported_root_visual_novel_id_fkey FOREIGN KEY (imported_root_visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE SET NULL;


--
-- Name: vn_series_items_hist vn_series_items_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_items_hist
    ADD CONSTRAINT vn_series_items_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_series_items_hist vn_series_items_hist_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_items_hist
    ADD CONSTRAINT vn_series_items_hist_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_series_items vn_series_items_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_items
    ADD CONSTRAINT vn_series_items_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_series_items vn_series_items_vn_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_items
    ADD CONSTRAINT vn_series_items_vn_series_id_fkey FOREIGN KEY (vn_series_id) REFERENCES public.vn_series(id) ON DELETE CASCADE;


--
-- Name: vn_series_producers_hist vn_series_producers_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_producers_hist
    ADD CONSTRAINT vn_series_producers_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_series_producers_hist vn_series_producers_hist_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_producers_hist
    ADD CONSTRAINT vn_series_producers_hist_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE CASCADE;


--
-- Name: vn_series_producers vn_series_producers_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_producers
    ADD CONSTRAINT vn_series_producers_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE CASCADE;


--
-- Name: vn_series_producers vn_series_producers_vn_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_series_producers
    ADD CONSTRAINT vn_series_producers_vn_series_id_fkey FOREIGN KEY (vn_series_id) REFERENCES public.vn_series(id) ON DELETE CASCADE;


--
-- Name: vn_similarities vn_similarities_similar_vn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarities
    ADD CONSTRAINT vn_similarities_similar_vn_id_fkey FOREIGN KEY (similar_vn_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_similarities vn_similarities_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarities
    ADD CONSTRAINT vn_similarities_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_similarity_votes vn_similarity_votes_similar_vn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarity_votes
    ADD CONSTRAINT vn_similarity_votes_similar_vn_id_fkey FOREIGN KEY (similar_vn_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_similarity_votes vn_similarity_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarity_votes
    ADD CONSTRAINT vn_similarity_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vn_similarity_votes vn_similarity_votes_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_similarity_votes
    ADD CONSTRAINT vn_similarity_votes_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_tag_votes vn_tag_votes_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tag_votes
    ADD CONSTRAINT vn_tag_votes_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: vn_tag_votes vn_tag_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tag_votes
    ADD CONSTRAINT vn_tag_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vn_tag_votes vn_tag_votes_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tag_votes
    ADD CONSTRAINT vn_tag_votes_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_tags vn_tags_overruled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tags
    ADD CONSTRAINT vn_tags_overruled_by_fkey FOREIGN KEY (overruled_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vn_tags vn_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tags
    ADD CONSTRAINT vn_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: vn_tags vn_tags_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_tags
    ADD CONSTRAINT vn_tags_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_titles_hist vn_titles_hist_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_titles_hist
    ADD CONSTRAINT vn_titles_hist_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.changes(id) ON DELETE CASCADE;


--
-- Name: vn_titles vn_titles_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_titles
    ADD CONSTRAINT vn_titles_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vn_versions vn_versions_reviewed_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_versions
    ADD CONSTRAINT vn_versions_reviewed_by_user_id_fkey FOREIGN KEY (reviewed_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vn_versions vn_versions_visual_novel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vn_versions
    ADD CONSTRAINT vn_versions_visual_novel_id_fkey FOREIGN KEY (visual_novel_id) REFERENCES public.visual_novels(id) ON DELETE CASCADE;


--
-- Name: vndb_imports vndb_imports_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vndb_imports
    ADD CONSTRAINT vndb_imports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict LFmIbLEl95wlJylgT6QdeAz0aHgUzUYOTSpM0TN64xNAdHzYuQJS5dKlT4OGAx9

INSERT INTO public."schema_migrations" (version) VALUES (20240716082328);
INSERT INTO public."schema_migrations" (version) VALUES (20240729112131);
INSERT INTO public."schema_migrations" (version) VALUES (20240729112132);
INSERT INTO public."schema_migrations" (version) VALUES (20240729112234);
INSERT INTO public."schema_migrations" (version) VALUES (20240729112236);
INSERT INTO public."schema_migrations" (version) VALUES (20240729112248);
INSERT INTO public."schema_migrations" (version) VALUES (20240729113412);
INSERT INTO public."schema_migrations" (version) VALUES (20240729113413);
INSERT INTO public."schema_migrations" (version) VALUES (20240729113415);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115241);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115425);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115440);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115506);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115714);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115908);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115929);
INSERT INTO public."schema_migrations" (version) VALUES (20240729115940);
INSERT INTO public."schema_migrations" (version) VALUES (20241120021630);
INSERT INTO public."schema_migrations" (version) VALUES (20250126161152);
INSERT INTO public."schema_migrations" (version) VALUES (20250206135855);
INSERT INTO public."schema_migrations" (version) VALUES (20250206140636);
INSERT INTO public."schema_migrations" (version) VALUES (20250216045926);
INSERT INTO public."schema_migrations" (version) VALUES (20250216063642);
INSERT INTO public."schema_migrations" (version) VALUES (20250305123637);
INSERT INTO public."schema_migrations" (version) VALUES (20250305130225);
INSERT INTO public."schema_migrations" (version) VALUES (20250314111606);
INSERT INTO public."schema_migrations" (version) VALUES (20250314111657);
INSERT INTO public."schema_migrations" (version) VALUES (20250315163144);
INSERT INTO public."schema_migrations" (version) VALUES (20250315163147);
INSERT INTO public."schema_migrations" (version) VALUES (20250315163150);
INSERT INTO public."schema_migrations" (version) VALUES (20250319134925);
INSERT INTO public."schema_migrations" (version) VALUES (20250328165423);
INSERT INTO public."schema_migrations" (version) VALUES (20250402143449);
INSERT INTO public."schema_migrations" (version) VALUES (20250402143548);
INSERT INTO public."schema_migrations" (version) VALUES (20250402143605);
INSERT INTO public."schema_migrations" (version) VALUES (20250402152608);
INSERT INTO public."schema_migrations" (version) VALUES (20250402152733);
INSERT INTO public."schema_migrations" (version) VALUES (20250604123930);
INSERT INTO public."schema_migrations" (version) VALUES (20250709152944);
INSERT INTO public."schema_migrations" (version) VALUES (20250714092827);
INSERT INTO public."schema_migrations" (version) VALUES (20250714135617);
INSERT INTO public."schema_migrations" (version) VALUES (20250715153122);
INSERT INTO public."schema_migrations" (version) VALUES (20250717084149);
INSERT INTO public."schema_migrations" (version) VALUES (20250717165441);
INSERT INTO public."schema_migrations" (version) VALUES (20250718091357);
INSERT INTO public."schema_migrations" (version) VALUES (20250718120237);
INSERT INTO public."schema_migrations" (version) VALUES (20250723120331);
INSERT INTO public."schema_migrations" (version) VALUES (20250723123809);
INSERT INTO public."schema_migrations" (version) VALUES (20250723133334);
INSERT INTO public."schema_migrations" (version) VALUES (20250801142537);
INSERT INTO public."schema_migrations" (version) VALUES (20250803071938);
INSERT INTO public."schema_migrations" (version) VALUES (20250803072014);
INSERT INTO public."schema_migrations" (version) VALUES (20250803162317);
INSERT INTO public."schema_migrations" (version) VALUES (20250803162318);
INSERT INTO public."schema_migrations" (version) VALUES (20250807091029);
INSERT INTO public."schema_migrations" (version) VALUES (20250809122831);
INSERT INTO public."schema_migrations" (version) VALUES (20250909085138);
INSERT INTO public."schema_migrations" (version) VALUES (20250909111541);
INSERT INTO public."schema_migrations" (version) VALUES (20250915181954);
INSERT INTO public."schema_migrations" (version) VALUES (20250915182022);
INSERT INTO public."schema_migrations" (version) VALUES (20250915182308);
INSERT INTO public."schema_migrations" (version) VALUES (20250915182310);
INSERT INTO public."schema_migrations" (version) VALUES (20250915182311);
INSERT INTO public."schema_migrations" (version) VALUES (20250915193914);
INSERT INTO public."schema_migrations" (version) VALUES (20250915193916);
INSERT INTO public."schema_migrations" (version) VALUES (20250915220000);
INSERT INTO public."schema_migrations" (version) VALUES (20250923120000);
INSERT INTO public."schema_migrations" (version) VALUES (20250926100000);
INSERT INTO public."schema_migrations" (version) VALUES (20250926100001);
INSERT INTO public."schema_migrations" (version) VALUES (20250928121500);
INSERT INTO public."schema_migrations" (version) VALUES (20250928121501);
INSERT INTO public."schema_migrations" (version) VALUES (20250928121502);
INSERT INTO public."schema_migrations" (version) VALUES (20250928121503);
INSERT INTO public."schema_migrations" (version) VALUES (20250928130000);
INSERT INTO public."schema_migrations" (version) VALUES (20250930110000);
INSERT INTO public."schema_migrations" (version) VALUES (20251008175511);
INSERT INTO public."schema_migrations" (version) VALUES (20251008175627);
INSERT INTO public."schema_migrations" (version) VALUES (20251015120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251015130000);
INSERT INTO public."schema_migrations" (version) VALUES (20251027130000);
INSERT INTO public."schema_migrations" (version) VALUES (20251029120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251030120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251106120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090000);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090010);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090020);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090030);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090040);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090050);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090060);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090121);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090122);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090123);
INSERT INTO public."schema_migrations" (version) VALUES (20251112090124);
INSERT INTO public."schema_migrations" (version) VALUES (20251125090000);
INSERT INTO public."schema_migrations" (version) VALUES (20251127093000);
INSERT INTO public."schema_migrations" (version) VALUES (20251201120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251201120005);
INSERT INTO public."schema_migrations" (version) VALUES (20251201120020);
INSERT INTO public."schema_migrations" (version) VALUES (20251201130000);
INSERT INTO public."schema_migrations" (version) VALUES (20251205100000);
INSERT INTO public."schema_migrations" (version) VALUES (20251208103000);
INSERT INTO public."schema_migrations" (version) VALUES (20251211111445);
INSERT INTO public."schema_migrations" (version) VALUES (20251215120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251216103000);
INSERT INTO public."schema_migrations" (version) VALUES (20251216130000);
INSERT INTO public."schema_migrations" (version) VALUES (20251216130100);
INSERT INTO public."schema_migrations" (version) VALUES (20251217160000);
INSERT INTO public."schema_migrations" (version) VALUES (20251218121500);
INSERT INTO public."schema_migrations" (version) VALUES (20251218123000);
INSERT INTO public."schema_migrations" (version) VALUES (20251218131500);
INSERT INTO public."schema_migrations" (version) VALUES (20251218140000);
INSERT INTO public."schema_migrations" (version) VALUES (20251223110000);
INSERT INTO public."schema_migrations" (version) VALUES (20251223110010);
INSERT INTO public."schema_migrations" (version) VALUES (20251223110020);
INSERT INTO public."schema_migrations" (version) VALUES (20251223110030);
INSERT INTO public."schema_migrations" (version) VALUES (20251223120100);
INSERT INTO public."schema_migrations" (version) VALUES (20251224120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251224130000);
INSERT INTO public."schema_migrations" (version) VALUES (20251224150000);
INSERT INTO public."schema_migrations" (version) VALUES (20251224150100);
INSERT INTO public."schema_migrations" (version) VALUES (20251225160000);
INSERT INTO public."schema_migrations" (version) VALUES (20251225160100);
INSERT INTO public."schema_migrations" (version) VALUES (20251225160200);
INSERT INTO public."schema_migrations" (version) VALUES (20251225170000);
INSERT INTO public."schema_migrations" (version) VALUES (20251226081435);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130000);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130001);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130002);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130003);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130004);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130005);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130006);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130007);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130008);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130009);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130010);
INSERT INTO public."schema_migrations" (version) VALUES (20251229130011);
INSERT INTO public."schema_migrations" (version) VALUES (20251230130001);
INSERT INTO public."schema_migrations" (version) VALUES (20251230130002);
INSERT INTO public."schema_migrations" (version) VALUES (20251231120000);
INSERT INTO public."schema_migrations" (version) VALUES (20251231121000);
INSERT INTO public."schema_migrations" (version) VALUES (20251231130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260102120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260105130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260105130001);
INSERT INTO public."schema_migrations" (version) VALUES (20260106080452);
INSERT INTO public."schema_migrations" (version) VALUES (20260106100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260106100001);
INSERT INTO public."schema_migrations" (version) VALUES (20260108080009);
INSERT INTO public."schema_migrations" (version) VALUES (20260109100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260109100001);
INSERT INTO public."schema_migrations" (version) VALUES (20260109100002);
INSERT INTO public."schema_migrations" (version) VALUES (20260109100003);
INSERT INTO public."schema_migrations" (version) VALUES (20260109124421);
INSERT INTO public."schema_migrations" (version) VALUES (20260109124814);
INSERT INTO public."schema_migrations" (version) VALUES (20260109135413);
INSERT INTO public."schema_migrations" (version) VALUES (20260109190143);
INSERT INTO public."schema_migrations" (version) VALUES (20260114080252);
INSERT INTO public."schema_migrations" (version) VALUES (20260116100455);
INSERT INTO public."schema_migrations" (version) VALUES (20260120130304);
INSERT INTO public."schema_migrations" (version) VALUES (20260121083554);
INSERT INTO public."schema_migrations" (version) VALUES (20260121083555);
INSERT INTO public."schema_migrations" (version) VALUES (20260121083556);
INSERT INTO public."schema_migrations" (version) VALUES (20260121183633);
INSERT INTO public."schema_migrations" (version) VALUES (20260122171853);
INSERT INTO public."schema_migrations" (version) VALUES (20260126120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260126124244);
INSERT INTO public."schema_migrations" (version) VALUES (20260126180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260128085304);
INSERT INTO public."schema_migrations" (version) VALUES (20260129100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260129100001);
INSERT INTO public."schema_migrations" (version) VALUES (20260129191617);
INSERT INTO public."schema_migrations" (version) VALUES (20260211120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260212171057);
INSERT INTO public."schema_migrations" (version) VALUES (20260212180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260212190000);
INSERT INTO public."schema_migrations" (version) VALUES (20260213120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260216120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260219120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260220142619);
INSERT INTO public."schema_migrations" (version) VALUES (20260224135828);
INSERT INTO public."schema_migrations" (version) VALUES (20260224135832);
INSERT INTO public."schema_migrations" (version) VALUES (20260225101515);
INSERT INTO public."schema_migrations" (version) VALUES (20260226150000);
INSERT INTO public."schema_migrations" (version) VALUES (20260302074723);
INSERT INTO public."schema_migrations" (version) VALUES (20260302143523);
INSERT INTO public."schema_migrations" (version) VALUES (20260303160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260303170948);
INSERT INTO public."schema_migrations" (version) VALUES (20260304190913);
INSERT INTO public."schema_migrations" (version) VALUES (20260305090033);
INSERT INTO public."schema_migrations" (version) VALUES (20260306081827);
INSERT INTO public."schema_migrations" (version) VALUES (20260309115638);
INSERT INTO public."schema_migrations" (version) VALUES (20260309160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260310170000);
INSERT INTO public."schema_migrations" (version) VALUES (20260310180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260310190000);
INSERT INTO public."schema_migrations" (version) VALUES (20260316200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260316210000);
INSERT INTO public."schema_migrations" (version) VALUES (20260317120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260317130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260317140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260319135029);
INSERT INTO public."schema_migrations" (version) VALUES (20260319140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260324000005);
INSERT INTO public."schema_migrations" (version) VALUES (20260324000006);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000001);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000002);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000003);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000004);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000005);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000006);
INSERT INTO public."schema_migrations" (version) VALUES (20260326000007);
INSERT INTO public."schema_migrations" (version) VALUES (20260330102138);
INSERT INTO public."schema_migrations" (version) VALUES (20260330120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260330140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260331000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260331000001);
INSERT INTO public."schema_migrations" (version) VALUES (20260331000002);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100001);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100002);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100003);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100004);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100005);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100006);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100007);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100008);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100009);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100010);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100011);
INSERT INTO public."schema_migrations" (version) VALUES (20260403200001);
INSERT INTO public."schema_migrations" (version) VALUES (20260403200002);
INSERT INTO public."schema_migrations" (version) VALUES (20260403200003);
INSERT INTO public."schema_migrations" (version) VALUES (20260404101422);
INSERT INTO public."schema_migrations" (version) VALUES (20260404114723);
INSERT INTO public."schema_migrations" (version) VALUES (20260405000001);
INSERT INTO public."schema_migrations" (version) VALUES (20260406000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260406131217);
INSERT INTO public."schema_migrations" (version) VALUES (20260408150458);
INSERT INTO public."schema_migrations" (version) VALUES (20260408184013);
INSERT INTO public."schema_migrations" (version) VALUES (20260409003700);
INSERT INTO public."schema_migrations" (version) VALUES (20260409110840);
INSERT INTO public."schema_migrations" (version) VALUES (20260409120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260409200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260413182946);
INSERT INTO public."schema_migrations" (version) VALUES (20260414192140);
INSERT INTO public."schema_migrations" (version) VALUES (20260415142757);
INSERT INTO public."schema_migrations" (version) VALUES (20260420160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260421130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260421200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260422920000);
INSERT INTO public."schema_migrations" (version) VALUES (20260422930000);
INSERT INTO public."schema_migrations" (version) VALUES (20260423000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260426000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260426120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260427130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260427142049);
INSERT INTO public."schema_migrations" (version) VALUES (20260427160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260427180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260428100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260428131846);
INSERT INTO public."schema_migrations" (version) VALUES (20260428200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260428210000);
INSERT INTO public."schema_migrations" (version) VALUES (20260429000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260429205148);
INSERT INTO public."schema_migrations" (version) VALUES (20260430164859);
INSERT INTO public."schema_migrations" (version) VALUES (20260430164900);
INSERT INTO public."schema_migrations" (version) VALUES (20260430200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260430221320);
INSERT INTO public."schema_migrations" (version) VALUES (20260501000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260501000001);
INSERT INTO public."schema_migrations" (version) VALUES (20260501100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260501160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260502120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260502130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260504140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260504143000);
INSERT INTO public."schema_migrations" (version) VALUES (20260504180000);
INSERT INTO public."schema_migrations" (version) VALUES (20260504223000);
INSERT INTO public."schema_migrations" (version) VALUES (20260504233000);
INSERT INTO public."schema_migrations" (version) VALUES (20260505010000);
INSERT INTO public."schema_migrations" (version) VALUES (20260505010001);
INSERT INTO public."schema_migrations" (version) VALUES (20260505120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260505223000);
INSERT INTO public."schema_migrations" (version) VALUES (20260505233000);
INSERT INTO public."schema_migrations" (version) VALUES (20260506120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260506140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260506150000);
INSERT INTO public."schema_migrations" (version) VALUES (20260514115234);
INSERT INTO public."schema_migrations" (version) VALUES (20260514203642);
INSERT INTO public."schema_migrations" (version) VALUES (20260521042521);
INSERT INTO public."schema_migrations" (version) VALUES (20260522065554);
INSERT INTO public."schema_migrations" (version) VALUES (20260522073624);
INSERT INTO public."schema_migrations" (version) VALUES (20260522080447);
INSERT INTO public."schema_migrations" (version) VALUES (20260523074558);
INSERT INTO public."schema_migrations" (version) VALUES (20260524035741);
INSERT INTO public."schema_migrations" (version) VALUES (20260618073912);
INSERT INTO public."schema_migrations" (version) VALUES (20260618073913);
INSERT INTO public."schema_migrations" (version) VALUES (20260621120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260621130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260622070728);
INSERT INTO public."schema_migrations" (version) VALUES (20260622100248);
INSERT INTO public."schema_migrations" (version) VALUES (20260624044341);
