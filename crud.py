import asyncpg
from typing import Optional, Any
from datetime import datetime


async def get_or_create_user(pool: asyncpg.Pool, telegram_id: int, full_name: str, username: str) -> int:
    """Возвращает ID пользователя, создавая его, если он не существует."""
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT a_user_id FROM main.get_user_id($1, $2, $3)",
            telegram_id, full_name, username,
        )
        if row:
            return row['a_user_id']


async def set_price_date(pool, tg_id: int, price_date) -> str | None:
    """
    Сохраняет дату для заполнения price_date.
    price_date=None сбрасывает в текущую дату.
    Возвращает текст ошибки или None.
    """
    async with pool.acquire() as conn:
        result = await conn.fetchval(
            "SELECT main.set_price_date($1, $2)",
            tg_id, price_date,
        )
        return result


async def get_default_shop(pool, user_id: int):
    """Возвращает (shop_name, price_date, err_msg)."""
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT a_shop_name, a_price_date, a_err_msg "
            "FROM main.get_default_shop($1)",
            user_id,
        )
        if row:
            return row['a_shop_name'], row['a_price_date'], row['a_err_msg']
        return None, None, "Не удалось получить результат"


async def add_shop(
    pool: asyncpg.Pool,
    shop_name: str,
    shop_address: str,
    telegram_id: int,
    address_id: int | None = None,
) -> tuple[int | None, str | None]:
    """
    Добавляет (address_id=None) или изменяет (address_id задан) магазин.
    Возвращает (shop_id, error_message).
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM main.upsert_shop($1, $2, $3, $4)",
            shop_name.strip(),
            shop_address.strip(),
            telegram_id,
            address_id,
        )
        if row:
            return row['a_shop_id'], row['a_err_msg']
        return None, "Не удалось получить результат"


async def call_upsert_product(
    pool: asyncpg.Pool,
    product_name: str,
    unit: str,
    qty: float,
    tg_id: int,
    product_id: int | None = None,
) -> tuple[int | None, str | None]:
    """
    Вызывает хранимую функцию main.upsert_product.
    Если product_id=None — добавление, иначе — обновление существующего.
    Возвращает (product_id, error_message).
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM main.upsert_product($1, $2, $3, $4, $5)",
            product_name.strip(),
            unit.strip(),
            qty,
            tg_id,
            product_id,
        )
        if row:
            return row['a_product_id'], row['a_err_msg']
        return None, "Не удалось получить результат"


async def get_shop_names(pool: asyncpg.Pool) -> list[dict[str, Any]]:
    """Возвращает список уникальных названий сетей."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT a_shop_id AS shop_id, a_shop_name AS shop_name "
            "FROM main.get_shop_names()"
        )
        return [
            {'shop_id': row['shop_id'], 'shop_name': row['shop_name']}
            for row in rows
        ]


async def get_shop_addresses(pool: asyncpg.Pool, shop_id: int) -> list[dict[str, Any]]:
    """Возвращает список адресов для указанной сети (id и address)."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT a_address_id AS address_id, a_address_name AS address_name "
            "FROM main.get_shop_addresses($1)",
            shop_id,
        )
        return [
            {'address_id': row['address_id'], 'address_name': row['address_name']}
            for row in rows
        ]


async def set_default_shop(pool: asyncpg.Pool, tg_id: int, address_id: int) -> str:
    """Сохраняет выбранный магазин для пользователя. Возвращает '' или текст ошибки."""
    async with pool.acquire() as conn:
        result = await conn.fetchval(
            "SELECT main.set_default_shop($1, $2)",
            tg_id, address_id,
        )
        return result


async def call_search_products(pool, search_text: str) -> list[dict]:
    """
    Поиск товаров по строке с префиксами.
    Возвращает product_id, product_name, product_qty, product_unit.
    """
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT a_product_id   AS product_id, "
            "       a_product_name AS product_name, "
            "       a_qty          AS product_qty, "
            "       a_unit_name    AS product_unit "
            "FROM main.get_products_byname($1)",
            search_text,
        )
        return [
            {
                "product_id":   row["product_id"],
                "product_name": row["product_name"],
                "product_qty":  row["product_qty"],
                "product_unit": row["product_unit"],
            }
            for row in rows
        ]


async def call_get_product_prices(pool, product_id: int) -> list[dict]:
    """Получение цен с цветовыми метками."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT a_shop_name  AS shop_name, "
            "       a_price      AS price, "
            "       a_price_date AS price_date, "
            "       a_color_name AS color_name "
            "FROM main.get_product_prices($1)",
            product_id,
        )
        return [
            {
                "shop_name":  row["shop_name"],
                "price":      row["price"],
                "price_date": row["price_date"],
                "color_name": row["color_name"],
            }
            for row in rows
        ]


async def call_add_price_by_product(
    pool,
    product_id: int,
    price: float,
    tg_id: int,
) -> tuple[int | None, str | None]:
    """Добавляет цену для продукта (по умолчанию магазин)."""
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM main.put_price_by_product($1, $2, $3)",
            product_id, price, tg_id,
        )
        if row:
            return row["a_shop_id"], row["a_err_msg"]
        return None, "Не удалось получить результат"


async def call_get_prices_report(
    pool,
    tg_id: int,
    search_text: str | None = None,
) -> tuple[str | None, str | None]:
    """
    Вызывает хранимую функцию get_prices_report.
    search_text — tsquery-строка ("вода:* & газ:*") или None (все товары).
    Возвращает (html_text, error_message).
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT a_html, a_err_msg FROM main.get_prices_report($1, $2)",
            tg_id, search_text,
        )
        if row:
            return row['a_html'], row['a_err_msg']
        return None, "Не удалось получить результат"