import asyncpg
from asyncpg import Pool
from typing import Optional

from dotenv import load_dotenv
import os

load_dotenv()

# DATABASE_URL = os.getenv("DATABASE_URL")

# Глобальная переменная для пула соединений
db_pool: Optional[Pool] = None

async def init_db():
    """Инициализирует пул соединений с базой данных."""
    global db_pool
    try:
#         db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5)
        db_pool = await asyncpg.create_pool(database="price_base", port=5433, user="price_base", min_size=1, max_size=5)
        print("✅ Подключение к базе данных установлено.")
    except Exception as e:
        print(f"❌ Ошибка подключения к базе данных: {e}")
        raise

async def get_pool() -> Pool:
    """Возвращает пул соединений."""
    if db_pool is None:
        await init_db()
    return db_pool