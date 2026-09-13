--
-- PostgreSQL database dump
--

-- Dumped from database version 12.22 (Ubuntu 12.22-0ubuntu0.20.04.4)
-- Dumped by pg_dump version 13.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: main; Type: SCHEMA; Schema: -; Owner: supusr
--

CREATE SCHEMA main;


ALTER SCHEMA main OWNER TO supusr;

--
-- Name: get_default_shop(bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_default_shop(p_telegram_id bigint) RETURNS TABLE(a_address_id bigint, a_shop_name text, a_price_date date, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_err_msg text;
	v_rows_returned int;
BEGIN

	select *
	into v_user_id, v_err_msg
	from main.get_user_bytg(p_telegram_id);

    IF v_err_msg IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, null::text, null::date, v_err_msg;
        RETURN;
    END IF;

	RETURN QUERY
		SELECT a.address_id, s.shop_name||', '||a.address_name, u.price_date, null::TEXT
		from main.users u
		inner join main.addresses a
			on a.address_id = u.shop_address_id
		inner join main.shops s
			on s.shop_id = a.shop_id 
		where u.user_id = v_user_id;

	GET DIAGNOSTICS v_rows_returned = ROW_COUNT;

	if v_rows_returned = 0 then
		RETURN QUERY SELECT null::bigint, null::text, null::date, 'Ссылка недействительна.';
		RETURN;
	end if;

	RETURN;

EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, null::text, null::date, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_default_shop(p_telegram_id bigint) OWNER TO supusr;

--
-- Name: get_prices_report(bigint, text); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_prices_report(p_tg_id bigint, p_search_text text DEFAULT NULL::text) RETURNS TABLE(a_html text, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_html TEXT;
BEGIN

    v_html := '<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Отчёт по ценам</title>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; color: #2c3e50; }
  h1 { color: #2c3e50; }
  .product-block {
      margin-bottom: 35px;
      padding-bottom: 25px;
      border-bottom: 1px dashed #ccc;
  }
  .product-block:last-child {
      border-bottom: none;
      padding-bottom: 0;
  }
  .product-block h2 {
      margin: 0 0 4px 0;
      color: #2c3e50;
      font-size: 18px;
  }
  .product-block .meta {
      margin: 0 0 12px 0;
      color: #666;
      font-size: 14px;
  }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
  th { background: #f4f4f4; }
  tr:nth-child(even) { background: #fafafa; }
  .price { text-align: right; color: #27ae60; font-weight: bold; }
  .empty { color: #999; font-style: italic; }
</style>
</head>
<body>
<h1>Отчёт по ценам</h1>
<p>Сформирован: ' || to_char(now(), 'DD.MM.YYYY HH24:MI') || '</p>';

    IF p_search_text IS NOT NULL THEN
        v_html := v_html || '<p>Фильтр: <b>' || p_search_text || '</b></p>';
    END IF;

    -- Блоки по каждому товару, собираем их в один HTML через string_agg
    v_html := v_html || COALESCE((
        SELECT string_agg(product_block, E'\n' ORDER BY product_name)
        FROM (
            SELECT
                prd.a_product_name AS product_name,
                '<div class="product-block">' ||
                '<h2>' || prd.a_product_name || '</h2>' ||
                '<p class="meta">Единица измерения: <b>' || u.unit_name ||
                '</b> &nbsp;|&nbsp; Количество: <b>' ||
                to_char(p.qty, 'FM999999990.00') || '</b></p>' ||
                '<table>' ||
                '<thead>' ||
                '<tr><th>Магазин</th><th>Цена</th><th>Дата</th></tr>' ||
                '</thead>' ||
                '<tbody>' ||
                COALESCE((
                    SELECT string_agg(
                        '<tr><td>' || prc.a_shop_name ||
                        '</td><td class="price">' ||
                        to_char(prc.a_price, 'FM999999990.00') ||
                        '</td><td>' ||
                        to_char(prc.a_price_date, 'DD.MM.YYYY') ||
                        '</td></tr>',
                        '' ORDER BY prc.a_price
                    )
                    FROM main.get_product_prices(prd.a_product_id) prc
                ), '<tr><td colspan="3" class="empty">Нет данных о ценах</td></tr>') ||
                '</tbody></table>' ||
                '</div>' AS product_block
            FROM main.get_products_byname(p_search_text) prd
            INNER JOIN main.products p ON p.product_id = prd.a_product_id
            INNER JOIN main.units u    ON u.unit_id    = p.unit_id
        ) sub
    ), '<p class="empty">По заданному фильтру товары не найдены.</p>');

    v_html := v_html || '</body></html>';

    RETURN QUERY SELECT v_html, NULL::TEXT;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::TEXT, SQLERRM;
END;
$$;


ALTER FUNCTION main.get_prices_report(p_tg_id bigint, p_search_text text) OWNER TO supusr;

--
-- Name: get_product_prices(bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_product_prices(p_product_id bigint) RETURNS TABLE(a_shop_name text, a_price numeric, a_price_date timestamp without time zone, a_color_name text, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_banned boolean;
BEGIN

	RETURN QUERY
		with last_prc as
		(
			select prc.product_id, adr.shop_id, prc.price_date, prc.price,
				row_number() over (partition by prc.product_id, adr.shop_id order by prc.price_date desc) rn
			from main.prices prc
			inner join main.addresses adr
				on adr.address_id = prc.address_id
			where prc.product_id = p_product_id
		)
		select shp.shop_name, prc.price, prc.price_date::timestamp, null::text, null::text
		from last_prc prc
		inner join main.shops shp
			on shp.shop_id = prc.shop_id
		where prc.rn = 1
		order by prc.price;
	RETURN;

    --RETURN QUERY SELECT v_user_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::text, null::numeric(19, 6), null::timestamp, null::text, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_product_prices(p_product_id bigint) OWNER TO supusr;

--
-- Name: get_products_byname(text); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_products_byname(p_search_txt text) RETURNS TABLE(a_product_id bigint, a_product_name text, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_banned boolean;
BEGIN

	RETURN QUERY
		SELECT product_id, product_name, null::TEXT
		from main.products
		where to_tsvector('multilingual', product_name)
   				@@ to_tsquery('multilingual', p_search_txt)
		  or p_search_txt is null
		order by product_name;
	RETURN;

    --RETURN QUERY SELECT v_user_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, null::text, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_products_byname(p_search_txt text) OWNER TO supusr;

--
-- Name: get_shop_addresses(bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_shop_addresses(p_shop_id bigint) RETURNS TABLE(a_address_id bigint, a_address_name text, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_banned boolean;
BEGIN

	RETURN QUERY 
		SELECT address_id, address_name, null::TEXT
		from main.addresses
		where shop_id = p_shop_id
		order by address_name;
	RETURN;

    --RETURN QUERY SELECT v_user_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, null::text, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_shop_addresses(p_shop_id bigint) OWNER TO supusr;

--
-- Name: get_shop_names(); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_shop_names() RETURNS TABLE(a_shop_id bigint, a_shop_name text, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_banned boolean;
BEGIN

	RETURN QUERY 
		SELECT shop_id, shop_name, null::TEXT
		from main.shops
		order by shop_name;
	RETURN;

    --RETURN QUERY SELECT v_user_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, null::text, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_shop_names() OWNER TO supusr;

--
-- Name: get_user_bytg(bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_user_bytg(p_telegram_id bigint) RETURNS TABLE(a_user_id bigint, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_banned boolean;
BEGIN

	select user_id, banned
	into v_user_id,	v_banned
	from main.users
	where telegram_id = p_telegram_id;

    IF v_banned IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, 'Данный пользователь заблокирован.'::TEXT;
        RETURN;
    END IF;

    IF v_user_id IS NULL THEN
        RETURN QUERY SELECT null::bigint, 'Пользователя нет в БД.'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT v_user_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_user_bytg(p_telegram_id bigint) OWNER TO supusr;

--
-- Name: get_user_id(bigint, text, text); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.get_user_id(p_telegram_id bigint, p_full_name text, p_user_name text) RETURNS TABLE(a_user_id bigint, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_banned boolean;
BEGIN
/*
	INSERT INTO main.users (telegram_id, full_name, user_name)
	select p_telegram_id, p_full_name, p_user_name
	where not exists (select 1 from main.users x where x.telegram_id = p_telegram_id)
	ON CONFLICT (telegram_id) DO NOTHING;

*/
	WITH updated AS (
	    UPDATE main.users
	    SET full_name = p_full_name,
	        user_name = p_user_name
	    WHERE telegram_id = p_telegram_id
		  and md5(row(full_name, user_name)::text) != md5(row(p_full_name, p_user_name)::text)
	    RETURNING user_id, banned
	),
	inserted AS (
	    INSERT INTO main.users (telegram_id, full_name, user_name)
	    SELECT p_telegram_id, p_full_name, p_user_name
	    WHERE NOT EXISTS (SELECT 1 FROM updated)   -- если UPDATE ничего не вернул
	    RETURNING user_id, null::boolean as banned
	),
	tot as (
		SELECT user_id, banned FROM updated
		UNION ALL
		SELECT user_id, banned FROM inserted
	)
	select user_id, banned
	into v_user_id, v_banned
	from (
		select user_id, banned
		from tot
		union all
		select user_id, banned
		from main.users
		where telegram_id = p_telegram_id
		  and not exists (select 1 from tot)
	) q;

    IF v_banned IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, 'Данный пользователь заблокирован.'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT v_user_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.get_user_id(p_telegram_id bigint, p_full_name text, p_user_name text) OWNER TO supusr;

--
-- Name: put_price_by_product(bigint, numeric, bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.put_price_by_product(p_product_id bigint, p_price numeric, p_telegram_id bigint) RETURNS TABLE(a_shop_id bigint, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_address_id BIGINT;
	v_err_msg text;
	v_price_date date;
BEGIN
	
	select *
	into v_user_id, v_err_msg
	from main.get_user_bytg(p_telegram_id);

    IF v_err_msg IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, v_err_msg;
        RETURN;
    END IF;

	select x.a_address_id, coalesce(x.a_price_date, CURRENT_TIMESTAMP::date), x.a_err_msg
	into v_address_id, v_price_date, v_err_msg
	from main.get_default_shop(p_telegram_id) x;

    IF v_err_msg IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, v_err_msg;
        RETURN;
    END IF;

	INSERT INTO main.prices (product_id, address_id, price_date, price, created_by, updated_by)
	select p_product_id, v_address_id, v_price_date, p_price, v_user_id, v_user_id
	ON CONFLICT (product_id, address_id, price_date)
	DO UPDATE SET price = EXCLUDED.price, updated_by = v_user_id;

    RETURN QUERY SELECT v_address_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.put_price_by_product(p_product_id bigint, p_price numeric, p_telegram_id bigint) OWNER TO supusr;

--
-- Name: set_default_shop(bigint, bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.set_default_shop(p_telegram_id bigint, p_address_id bigint) RETURNS TABLE(a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_err_msg text;
BEGIN
	
	select *
	into v_user_id, v_err_msg
	from main.get_user_bytg(p_telegram_id);

    IF v_err_msg IS NOT NULL THEN
        RETURN QUERY SELECT v_err_msg;
        RETURN;
    END IF;

	if not exists (select 1 from main.addresses where address_id = p_address_id) then
        RETURN QUERY SELECT 'Адрес не найден.';
        RETURN;
	end if;


	update main.users
	set shop_address_id = p_address_id
	where user_id = v_user_id
	  and row(shop_address_id)::text != row(p_address_id)::text;


    RETURN QUERY SELECT NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.set_default_shop(p_telegram_id bigint, p_address_id bigint) OWNER TO supusr;

--
-- Name: set_price_date(bigint, date); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.set_price_date(p_telegram_id bigint, p_price_date date DEFAULT NULL::date) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_err_msg text;
BEGIN

	select *
	into v_user_id, v_err_msg
	from main.get_user_bytg(p_telegram_id);

    IF v_err_msg IS NOT NULL THEN
        RETURN v_err_msg;
    END IF;


	update main.users
	set price_date = p_price_date
	where user_id = v_user_id
	  and row(price_date)::text != row(p_price_date)::text;

    RETURN NULL;   -- NULL = успех
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END;
$$;


ALTER FUNCTION main.set_price_date(p_telegram_id bigint, p_price_date date) OWNER TO supusr;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION main.update_updated_at_column() OWNER TO supusr;

--
-- Name: upsert_product(text, text, numeric, bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.upsert_product(p_product_name text, p_unit_name text, p_qty numeric, p_telegram_id bigint) RETURNS TABLE(a_product_id bigint, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_unit_id BIGINT;
	v_product_id BIGINT;
	v_banned boolean;
	v_err_msg text;
BEGIN
	
	select *
	into v_user_id, v_err_msg
	from main.get_user_bytg(p_telegram_id);

    IF v_err_msg IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, v_err_msg;
        RETURN;
    END IF;

	select unit_id
	into v_unit_id
	from main.units
	where lower(unit_name) = lower(p_unit_name);

	if v_unit_id is null then
		insert into main.units (unit_name, created_by, updated_by)
		select p_unit_name, v_user_id, v_user_id
		returning unit_id into v_unit_id;
	end if;

	select product_id
	into v_product_id
	from main.products
	where lower(product_name) = lower(p_product_name);

	if v_product_id is null then
		insert into main.products (product_name, unit_id, qty, created_by, updated_by)
		select p_product_name, v_unit_id, p_qty, v_user_id, v_user_id
		returning product_id into v_product_id;
	end if;

    RETURN QUERY SELECT v_product_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.upsert_product(p_product_name text, p_unit_name text, p_qty numeric, p_telegram_id bigint) OWNER TO supusr;

--
-- Name: upsert_shop(text, text, bigint); Type: FUNCTION; Schema: main; Owner: supusr
--

CREATE FUNCTION main.upsert_shop(p_shop_name text, p_address text, p_telegram_id bigint) RETURNS TABLE(a_shop_id bigint, a_err_msg text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_user_id BIGINT;
	v_shop_id BIGINT;
	v_address_id BIGINT;
	v_banned boolean;
	v_err_msg text;
BEGIN
	
	select *
	into v_user_id, v_err_msg
	from main.get_user_bytg(p_telegram_id);

    IF v_err_msg IS NOT NULL THEN
        RETURN QUERY SELECT null::bigint, v_err_msg;
        RETURN;
    END IF;

	INSERT INTO main.shops (shop_name, created_by, updated_by)
	select p_shop_name, v_user_id, v_user_id
	where not exists (select 1 from main.shops x where lower(x.shop_name) = lower(p_shop_name))
	ON CONFLICT (lower(shop_name)) DO NOTHING
	RETURNING shop_id INTO v_shop_id;

	if v_shop_id is null then
		select shop_id
		into v_shop_id
		from main.shops
		where lower(shop_name) = lower(p_shop_name);
	end if;

	INSERT INTO main.addresses (shop_id, address_name, created_by, updated_by)
	select v_shop_id, p_address, v_user_id, v_user_id
	where not exists (select 1 from main.addresses x where x.shop_id = v_shop_id and lower(x.address_name) = lower(p_address))
	ON CONFLICT (shop_id, lower(address_name)) DO NOTHING
	RETURNING address_id INTO v_address_id;

    RETURN QUERY SELECT v_address_id, NULL::TEXT;
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT null::bigint, SQLERRM::TEXT;

END;
$$;


ALTER FUNCTION main.upsert_shop(p_shop_name text, p_address text, p_telegram_id bigint) OWNER TO supusr;

--
-- Name: multilingual; Type: TEXT SEARCH CONFIGURATION; Schema: public; Owner: supusr
--

CREATE TEXT SEARCH CONFIGURATION public.multilingual (
    PARSER = pg_catalog."default" );

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR asciiword WITH english_stem, russian_stem;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR word WITH russian_stem;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR numword WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR email WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR url WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR host WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR sfloat WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR version WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR hword_numpart WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR hword_part WITH russian_stem;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR hword_asciipart WITH english_stem, russian_stem;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR numhword WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR asciihword WITH english_stem, russian_stem;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR hword WITH russian_stem;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR url_path WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR file WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR "float" WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR "int" WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.multilingual
    ADD MAPPING FOR uint WITH simple;


ALTER TEXT SEARCH CONFIGURATION public.multilingual OWNER TO supusr;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: addresses; Type: TABLE; Schema: main; Owner: supusr
--

CREATE TABLE main.addresses (
    address_id bigint NOT NULL,
    shop_id bigint NOT NULL,
    address_name text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_by bigint
);


ALTER TABLE main.addresses OWNER TO supusr;

--
-- Name: addresses_address_id_seq; Type: SEQUENCE; Schema: main; Owner: supusr
--

ALTER TABLE main.addresses ALTER COLUMN address_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.addresses_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prices; Type: TABLE; Schema: main; Owner: supusr
--

CREATE TABLE main.prices (
    product_id bigint NOT NULL,
    address_id bigint NOT NULL,
    price_date date,
    unit_id bigint,
    price numeric(19,6) NOT NULL,
    qty numeric(19,6),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_by bigint
);


ALTER TABLE main.prices OWNER TO supusr;

--
-- Name: products; Type: TABLE; Schema: main; Owner: supusr
--

CREATE TABLE main.products (
    product_id bigint NOT NULL,
    product_name text NOT NULL,
    unit_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_by bigint,
    qty numeric(19,6) NOT NULL
);


ALTER TABLE main.products OWNER TO supusr;

--
-- Name: products_product_id_seq; Type: SEQUENCE; Schema: main; Owner: supusr
--

ALTER TABLE main.products ALTER COLUMN product_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.products_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: shops; Type: TABLE; Schema: main; Owner: supusr
--

CREATE TABLE main.shops (
    shop_id bigint NOT NULL,
    shop_name text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_by bigint
);


ALTER TABLE main.shops OWNER TO supusr;

--
-- Name: shops_shop_id_seq; Type: SEQUENCE; Schema: main; Owner: supusr
--

ALTER TABLE main.shops ALTER COLUMN shop_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.shops_shop_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: units; Type: TABLE; Schema: main; Owner: supusr
--

CREATE TABLE main.units (
    unit_id bigint NOT NULL,
    unit_name text NOT NULL,
    unit_desc text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_by bigint
);


ALTER TABLE main.units OWNER TO supusr;

--
-- Name: units_unit_id_seq; Type: SEQUENCE; Schema: main; Owner: supusr
--

ALTER TABLE main.units ALTER COLUMN unit_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.units_unit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: main; Owner: supusr
--

CREATE TABLE main.users (
    user_id bigint NOT NULL,
    telegram_id bigint,
    banned boolean,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_by bigint,
    full_name text,
    user_name text,
    shop_address_id bigint,
    price_date date
);


ALTER TABLE main.users OWNER TO supusr;

--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: main; Owner: supusr
--

ALTER TABLE main.users ALTER COLUMN user_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: main; Owner: supusr
--

ALTER TABLE ONLY main.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (address_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: main; Owner: supusr
--

ALTER TABLE ONLY main.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- Name: shops shops_pkey; Type: CONSTRAINT; Schema: main; Owner: supusr
--

ALTER TABLE ONLY main.shops
    ADD CONSTRAINT shops_pkey PRIMARY KEY (shop_id);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: main; Owner: supusr
--

ALTER TABLE ONLY main.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (unit_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: main; Owner: supusr
--

ALTER TABLE ONLY main.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: addresses_address_name_unique_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE UNIQUE INDEX addresses_address_name_unique_idx ON main.addresses USING btree (shop_id, lower(address_name));


--
-- Name: prices_unique_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE UNIQUE INDEX prices_unique_idx ON main.prices USING btree (product_id, address_id, price_date);


--
-- Name: products_product_name_gin_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE INDEX products_product_name_gin_idx ON main.products USING gin (to_tsvector('public.multilingual'::regconfig, product_name));


--
-- Name: products_product_name_unique_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE UNIQUE INDEX products_product_name_unique_idx ON main.products USING btree (lower(product_name));


--
-- Name: shops_shop_name_unique_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE UNIQUE INDEX shops_shop_name_unique_idx ON main.shops USING btree (lower(shop_name));


--
-- Name: units_unit_name_unique_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE UNIQUE INDEX units_unit_name_unique_idx ON main.units USING btree (lower(unit_name));


--
-- Name: users_telegram_id_unique_idx; Type: INDEX; Schema: main; Owner: supusr
--

CREATE UNIQUE INDEX users_telegram_id_unique_idx ON main.users USING btree (telegram_id);


--
-- Name: addresses trg_update_addresses_updated_at; Type: TRIGGER; Schema: main; Owner: supusr
--

CREATE TRIGGER trg_update_addresses_updated_at BEFORE UPDATE ON main.addresses FOR EACH ROW EXECUTE FUNCTION main.update_updated_at_column();


--
-- Name: prices trg_update_prices_updated_at; Type: TRIGGER; Schema: main; Owner: supusr
--

CREATE TRIGGER trg_update_prices_updated_at BEFORE UPDATE ON main.prices FOR EACH ROW EXECUTE FUNCTION main.update_updated_at_column();


--
-- Name: products trg_update_products_updated_at; Type: TRIGGER; Schema: main; Owner: supusr
--

CREATE TRIGGER trg_update_products_updated_at BEFORE UPDATE ON main.products FOR EACH ROW EXECUTE FUNCTION main.update_updated_at_column();


--
-- Name: shops trg_update_shops_updated_at; Type: TRIGGER; Schema: main; Owner: supusr
--

CREATE TRIGGER trg_update_shops_updated_at BEFORE UPDATE ON main.shops FOR EACH ROW EXECUTE FUNCTION main.update_updated_at_column();


--
-- Name: units trg_update_units_updated_at; Type: TRIGGER; Schema: main; Owner: supusr
--

CREATE TRIGGER trg_update_units_updated_at BEFORE UPDATE ON main.units FOR EACH ROW EXECUTE FUNCTION main.update_updated_at_column();


--
-- Name: users trg_update_users_updated_at; Type: TRIGGER; Schema: main; Owner: supusr
--

CREATE TRIGGER trg_update_users_updated_at BEFORE UPDATE ON main.users FOR EACH ROW EXECUTE FUNCTION main.update_updated_at_column();


--
-- Name: SCHEMA main; Type: ACL; Schema: -; Owner: supusr
--

GRANT USAGE ON SCHEMA main TO price_base;


--
-- PostgreSQL database dump complete
--

