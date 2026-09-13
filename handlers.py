import re
from typing import Union
from datetime import datetime, date

from aiogram import Router, types, F
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import StatesGroup, State
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery, Message, BufferedInputFile
from aiogram.exceptions import TelegramBadRequest
from aiogram.enums import ParseMode

from database import get_pool
import crud


router = Router()

# ------------------- Состояния -------------------
class AddPriceStates(StatesGroup):
    waiting_for_product = State()
    waiting_for_price = State()

class AddProductStates(StatesGroup):
    waiting_for_product_name = State()
    waiting_for_unit = State()

class PriceStates(StatesGroup):
    waiting_for_search_text = State()
    showing_prices = State()
    waiting_for_price = State()
    waiting_for_report_search = State()

class AddShopStates(StatesGroup):
    waiting_for_shop_name = State()
    waiting_for_shop_address = State()

class DateStates(StatesGroup):
    waiting_for_date = State()

# ------------------- Клавиатуры меню -------------------
def main_menu_keyboard() -> InlineKeyboardMarkup:
    buttons = [
        [InlineKeyboardButton(text="💰 Цены", callback_data="menu|prices")],
        [InlineKeyboardButton(text="🏪 Магазины", callback_data="menu|shops")],
        [InlineKeyboardButton(text="📦 Товары", callback_data="menu|products")],
        [InlineKeyboardButton(text="⚙️ Параметры", callback_data="menu|params")],
    ]
    return InlineKeyboardMarkup(inline_keyboard=buttons)

def submenu_keyboard(menu_name: str) -> InlineKeyboardMarkup:
    if menu_name == "prices":
        buttons = [
            [InlineKeyboardButton(text="📊 Просмотр", callback_data="action|prices_view")],
            [InlineKeyboardButton(text="➕ Ввод", callback_data="action|price_input")],
            [InlineKeyboardButton(text="🔙 Назад", callback_data="menu|main")],
        ]
    elif menu_name == "shops":
        buttons = [
            [InlineKeyboardButton(text="🔍 Выбрать", callback_data="action|shop_choose")],
            [InlineKeyboardButton(text="➕ Добавить", callback_data="action|shop_add")],
            [InlineKeyboardButton(text="✏️ Изменить", callback_data="action|dummy")],
            [InlineKeyboardButton(text="🔙 Назад", callback_data="menu|main")],
        ]
    elif menu_name == "products":
        buttons = [
            [InlineKeyboardButton(text="📊 Просмотр", callback_data="action|dummy")],
            [InlineKeyboardButton(text="➕ Добавить", callback_data="action|product_add")],
            [InlineKeyboardButton(text="✏️ Изменить", callback_data="action|dummy")],
            [InlineKeyboardButton(text="🔙 Назад", callback_data="menu|main")],
        ]
    elif menu_name == "params":
        buttons = [
            [InlineKeyboardButton(text="📍 Выбрать локацию", callback_data="action|dummy")],
            [InlineKeyboardButton(text="📋 Просмотр", callback_data="action|my_shop")],
            [InlineKeyboardButton(text="🏪 Выбрать магазин", callback_data="action|shop_choose")],
            [InlineKeyboardButton(text="📅 Установить дату", callback_data="action|set_date")],
            [InlineKeyboardButton(text="🔙 Назад", callback_data="menu|main")],
        ]
    else:
        buttons = []
    return InlineKeyboardMarkup(inline_keyboard=buttons)

def cancel_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_add")]
        ]
    )

def product_buttons(products: list[dict]) -> InlineKeyboardMarkup:
    buttons = [
        [InlineKeyboardButton(text=p['product_name'], callback_data=f"product|{p['product_id']}")]
        for p in products
    ]
    buttons.append([InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_add")])
    return InlineKeyboardMarkup(inline_keyboard=buttons)

def price_action_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="➕ Добавить цену", callback_data="add_price_for_product")],
            [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_add")]
        ]
    )

def report_search_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Все товары", callback_data="report_all")],
        [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_add")],
    ])


async def safe_edit(
    callback: CallbackQuery,
    text: str,
    reply_markup: InlineKeyboardMarkup | None = None,
    parse_mode: str | None = ParseMode.HTML,
) -> None:
    """
    Пытается отредактировать сообщение, на котором была нажата кнопка.
    Если это невозможно (например, это документ без текста) —
    отправляет новое сообщение с тем же содержимым.
    """
    msg = callback.message
    # У сообщения есть текст? Только тогда edit_text корректно сработает.
    if getattr(msg, "text", None):
        try:
            await msg.edit_text(text, reply_markup=reply_markup, parse_mode=parse_mode)
            return
        except TelegramBadRequest:
            # Мало ли что — например, текст не изменился, или сообщение слишком старое
            pass

    # Фолбэк: отправляем новое сообщение
    await msg.answer(text, reply_markup=reply_markup, parse_mode=parse_mode)


def date_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📆 Текущая дата", callback_data="date_reset")],
        [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_add")],
    ])


# ------------------- Команда /start -------------------
@router.message(Command("start"))
async def cmd_start(message: types.Message):
    pool = await get_pool()
    await crud.get_or_create_user(pool, message.from_user.id, message.from_user.full_name, message.from_user.username)
    await message.answer("🏠 Главное меню:", reply_markup=main_menu_keyboard())

# ------------------- Навигация по меню -------------------
@router.callback_query(F.data.startswith("menu|"))
async def menu_callback(callback: CallbackQuery):
    menu = callback.data.split("|")[1]
    if menu == "main":
        text = "🏠 Главное меню:"
        keyboard = main_menu_keyboard()
    else:
        menu_names = {
            "prices": "💰 Цены",
            "shops": "🏪 Магазины",
            "products": "📦 Товары",
            "params": "⚙️ Параметры",
        }
        text = f"Меню: {menu_names.get(menu, '')}"
        keyboard = submenu_keyboard(menu)
    await safe_edit(callback, text, reply_markup=keyboard)
    await callback.answer()


# ------------------- Действия из меню -------------------
@router.callback_query(F.data.startswith("action|"))
async def action_callback(callback: CallbackQuery, state: FSMContext):
    action = callback.data.split("|")[1]

    if action == "dummy":
        await safe_edit(callback, "⚠️ Функция в разработке.", reply_markup=main_menu_keyboard())
        await callback.answer()
        return

    if action == "price_input":
        await state.set_state(PriceStates.waiting_for_search_text)
        await safe_edit(
            callback,
            "🔍 Введите строку для поиска товара (например: «вода газ»):",
            reply_markup=cancel_keyboard(),
        )
        await callback.answer()

    elif action == "shop_choose":
        await show_shop_names(callback)

    elif action == "shop_add":
        await state.set_state(AddShopStates.waiting_for_shop_name)
        await safe_edit(callback, "🏪 Введите название магазина:", reply_markup=cancel_keyboard())
        await callback.answer()

    elif action == "product_add":
        await state.set_state(AddProductStates.waiting_for_product_name)
        await safe_edit(callback, "🛒 Введите название товара:", reply_markup=cancel_keyboard())
        await callback.answer()

    elif action == "set_date":
        await state.set_state(DateStates.waiting_for_date)
        await safe_edit(
            callback,
            "📅 Введите дату в формате <b>ДД.ММ.ГГГГ</b> (например: 15.08.2025).\n\n"
            "Эта дата будет использоваться при добавлении цен.\n"
            "Или нажмите «Текущая дата», чтобы сбросить параметр:",
            reply_markup=date_keyboard(),
        )
        await callback.answer()

    elif action == "my_shop":
        pool = await get_pool()
        shop_name, price_date, err_msg = await crud.get_default_shop(pool, callback.from_user.id)
        text = format_shop_info(shop_name, price_date, err_msg)
        await safe_edit(callback, text, reply_markup=main_menu_keyboard())
        await callback.answer()

    elif action == "prices_view":
        await state.set_state(PriceStates.waiting_for_report_search)
        await safe_edit(
            callback,
            "🔍 Введите строку для поиска товара\n"
            "(например: «вода газ»).\n\n"
            "Или нажмите «Все товары», чтобы выгрузить полный отчёт:",
            reply_markup=report_search_keyboard(),
        )
        await callback.answer()

    else:
        await callback.answer("Неизвестное действие", show_alert=True)


def format_shop_info(shop_name, price_date, err_msg) -> str:
    if err_msg:
        return f"❌ {err_msg}"
    date_str = price_date.strftime("%d.%m.%Y") if price_date else "Текущая дата"
    return (
        f"🏪 Магазин по умолчанию: <b>{shop_name or '—'}</b>\n"
        f"📅 Дата ввода цен: <b>{date_str}</b>"
    )


# ------------------- Отмена действия (возврат в главное меню) -------------------
@router.callback_query(F.data == "cancel_add")
async def cancel_add(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    await safe_edit(callback, "❌ Действие отменено.", reply_markup=main_menu_keyboard())
    await callback.answer()

# ------------------- Команда /add_shop (интерактивный) -------------------
@router.message(Command("add_shop"))
async def cmd_add_shop(message: Message, state: FSMContext):
    await state.set_state(AddShopStates.waiting_for_shop_name)
    await message.answer("🏪 Введите название магазина:", reply_markup=cancel_keyboard())

@router.message(AddShopStates.waiting_for_shop_name)
async def process_shop_name(message: Message, state: FSMContext):
    shop_name = message.text.strip()
    if not shop_name:
        await message.answer("❌ Название не может быть пустым. Попробуйте снова:", reply_markup=cancel_keyboard())
        return
    await state.update_data(shop_name=shop_name)
    await state.set_state(AddShopStates.waiting_for_shop_address)
    await message.answer("📍 Введите адрес магазина:", reply_markup=cancel_keyboard())

@router.message(AddShopStates.waiting_for_shop_address)
async def process_shop_address(message: Message, state: FSMContext):
    shop_address = message.text.strip()
    if not shop_address:
        await message.answer("❌ Адрес не может быть пустым. Попробуйте снова:", reply_markup=cancel_keyboard())
        return
    data = await state.get_data()
    shop_name = data.get('shop_name')
    pool = await get_pool()
    shop_id, err_msg = await crud.add_shop(pool, shop_name, shop_address, message.from_user.id)
    if err_msg:
        await message.answer(f"❌ Ошибка: {err_msg}")
    else:
        await message.answer(f"✅ Магазин «{shop_name}» сохранён (ID: {shop_id}).\nАдрес: {shop_address}")
    await state.clear()
    await message.answer("🏠 Главное меню:", reply_markup=main_menu_keyboard())

# ------------------- Команда /add_product (интерактивный) -------------------
@router.message(Command("add_product"))
async def cmd_add_product(message: Message, state: FSMContext):
    await state.set_state(AddProductStates.waiting_for_product_name)
    await message.answer("🛒 Введите название товара:", reply_markup=cancel_keyboard())

@router.message(AddProductStates.waiting_for_product_name)
async def process_product_name(message: Message, state: FSMContext):
    product_name = message.text.strip()
    if not product_name:
        await message.answer("❌ Название не может быть пустым. Попробуйте снова:", reply_markup=cancel_keyboard())
        return
    await state.update_data(product_name=product_name)
    await state.set_state(AddProductStates.waiting_for_unit)
    await message.answer("📦 Введите кол-во и единицу измерения (например: 1 кг, 100 шт, 1.5 л):", reply_markup=cancel_keyboard())

@router.message(AddProductStates.waiting_for_unit)
async def process_unit(message: Message, state: FSMContext):
    args = message.text.strip().split()
    if len(args) != 2:
        await message.answer("❌ Неверный формат. Используйте разделитель [пробел]\nПример: 1 кг, 100 шт, 1.5 л")
        return
    raw_qty = args[0].strip().replace(',', '.')
    if not re.match(r'^\d+\.?\d*$', raw_qty):
        await message.answer("❌ Неверный формат кол-ва. Введите число (например: 1.965):", reply_markup=cancel_keyboard())
        return
    qty = float(raw_qty)
    unit = args[1].strip()
    if not unit:
        await message.answer("❌ Единица измерения не может быть пустой. Попробуйте снова:", reply_markup=cancel_keyboard())
        return
    data = await state.get_data()
    product_name = data.get('product_name')
    pool = await get_pool()
    product_id, err_msg = await crud.call_upsert_product(pool, product_name, unit, qty, message.from_user.id)
    if err_msg:
        await message.answer(f"❌ Ошибка: {err_msg}")
    else:
        await message.answer(f"✅ Товар «{product_name}» (ед. изм. {unit}) сохранён (ID: {product_id}).")
    await state.clear()
    await message.answer("🏠 Главное меню:", reply_markup=main_menu_keyboard())

# ------------------- Выбор магазина (команда /choose_shop и навигация) -------------------
@router.message(Command("choose_shop"))
@router.callback_query(F.data == "back_to_shop_names")
async def show_shop_names(event: Union[types.Message, types.CallbackQuery]):
    pool = await get_pool()
    shop_names = await crud.get_shop_names(pool)

    is_callback = isinstance(event, types.CallbackQuery)
    message_obj = event.message if is_callback else event

    if not shop_names:
        text_empty = "❌ Нет доступных магазинов. Сначала добавьте их через /add_shop."
        if is_callback:
            await event.message.edit_text(text_empty, reply_markup=main_menu_keyboard())
            await event.answer()
        else:
            await event.answer(text_empty, reply_markup=main_menu_keyboard())
        return

    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=shop['shop_name'], callback_data=f"shop_select|{shop['shop_id']}")]
        for shop in shop_names
    ])
    text_msg = "🏪 Выберите сеть магазинов:"

    if is_callback:
        await safe_edit(event, text_msg, reply_markup=keyboard)
        await event.answer()
    else:
        await event.answer(text_msg, reply_markup=keyboard)

@router.callback_query(F.data.startswith("shop_select|"))
async def process_shop_select(callback: CallbackQuery):
    shop_id = int(callback.data.split("|", 1)[1])
    pool = await get_pool()
    addresses = await crud.get_shop_addresses(pool, shop_id)

    if not addresses:
        await callback.answer("Для этой сети нет адресов.", show_alert=True)
        return

    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=addr['address_name'], callback_data=f"address_select|{addr['address_id']}")]
        for addr in addresses
    ] + [
        [InlineKeyboardButton(text="🔙 Назад", callback_data="back_to_shop_names")]
    ])
    await safe_edit(callback, "📍 Адреса магазинов:", reply_markup=keyboard)
    await callback.answer()


@router.callback_query(F.data.startswith("address_select|"))
async def process_address_select(callback: CallbackQuery):
    address_id = int(callback.data.split("|", 1)[1])
    pool = await get_pool()
    err_msg = await crud.set_default_shop(pool, callback.from_user.id, address_id)
    if err_msg:
        await safe_edit(callback, f"❌ Ошибка: {err_msg}", reply_markup=main_menu_keyboard())
    else:
        await safe_edit(callback, "✅ Магазин успешно выбран и сохранён как основной.",
                        reply_markup=main_menu_keyboard())
    await callback.answer()

# ------------------- Команда /my_shop -------------------
@router.message(Command("my_shop"))
async def cmd_my_shop(message: types.Message):
    pool = await get_pool()
    shop_name, price_date, err_msg = await crud.get_default_shop(pool, message.from_user.id)
    await message.answer(
        format_shop_info(shop_name, price_date, err_msg),
        reply_markup=main_menu_keyboard(),
    )


# ------------------- Команда /price (интерактивный) -------------------
@router.message(Command("price"))
async def cmd_price(message: Message, state: FSMContext):
    await state.set_state(PriceStates.waiting_for_search_text)
    await message.answer("🔍 Введите строку для поиска товара (например: «вода газ»):", reply_markup=cancel_keyboard())

@router.message(PriceStates.waiting_for_search_text)
async def process_search_text(message: Message, state: FSMContext):
    raw_text = message.text.strip()
    if not raw_text:
        await message.answer("❌ Строка не может быть пустой. Попробуйте снова:", reply_markup=cancel_keyboard())
        return
    search_text = " & ".join(f"{word}:*" for word in raw_text.split())
    pool = await get_pool()
    products = await crud.call_search_products(pool, search_text)
    if not products:
        await message.answer("😕 Товары не найдены. Попробуйте другую строку:", reply_markup=cancel_keyboard())
        return
    await message.answer("📋 Найдены товары. Выберите один:", reply_markup=product_buttons(products))
    await state.set_state(PriceStates.showing_prices)
    await state.update_data(products=products)

@router.callback_query(PriceStates.showing_prices, F.data.startswith("product|"))
async def process_product_selection(callback: CallbackQuery, state: FSMContext):
    product_id = int(callback.data.split("|")[1])
    await state.update_data(product_id=product_id)
    pool = await get_pool()
    prices = await crud.call_get_product_prices(pool, product_id)

    if not prices:
        await callback.message.edit_text("❌ Для этого товара нет цен. Добавьте цену через кнопку ниже.")
        await callback.message.edit_reply_markup(reply_markup=price_action_keyboard())
        await callback.answer()
        return

    MAX_SHOP_LEN = 25
    MAX_DATE_LEN = 15
    MAX_PRICE_LEN = 14

    lines = ["<pre>"]
    header = (
        f"{'Магазин':<{MAX_SHOP_LEN}} "
        f"{'Цена':>{MAX_PRICE_LEN}} "
        f"{'Дата':^{MAX_DATE_LEN}} "
    )
    lines.append(header)
    lines.append("-" * (MAX_SHOP_LEN + 1 + MAX_PRICE_LEN + 1 + MAX_DATE_LEN))
    for p in prices:
        shop = p['shop_name'][:MAX_SHOP_LEN].ljust(MAX_SHOP_LEN)
        price = f"{p['price']:.2f}".rjust(MAX_PRICE_LEN)
        date = p['price_date'].strftime("%d.%m.%Y").center(MAX_DATE_LEN)
        lines.append(f"{shop}|{price}|{date}")
    lines.append("</pre>")
    text = "📊 <b>Цены на товар</b>:\n\n" + "\n".join(lines)

    await callback.message.edit_text(text, parse_mode="HTML", reply_markup=price_action_keyboard())
    await callback.answer()

@router.callback_query(PriceStates.showing_prices, F.data == "add_price_for_product")
async def request_price_input(callback: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    if "product_id" not in data:
        await callback.message.edit_text("❌ Ошибка: товар не выбран. Начните заново /price")
        await state.clear()
        await callback.answer()
        return
    await state.set_state(PriceStates.waiting_for_price)
    await callback.message.edit_text("💰 Введите цену (дробная часть через точку или запятую):", reply_markup=cancel_keyboard())
    await callback.answer()

@router.message(PriceStates.waiting_for_price)
async def process_price_input(message: Message, state: FSMContext):
    raw_price = message.text.strip().replace(',', '.')
    if not re.match(r'^\d+\.?\d*$', raw_price):
        await message.answer("❌ Неверный формат цены. Введите число (например: 89.90):", reply_markup=cancel_keyboard())
        return
    price = float(raw_price)
    data = await state.get_data()
    product_id = data.get("product_id")
    if not product_id:
        await message.answer("❌ Ошибка: товар не выбран. Начните заново /price")
        await state.clear()
        return
    pool = await get_pool()
    shop_id, err_msg = await crud.call_add_price_by_product(pool, product_id, price, message.from_user.id)
    if err_msg:
        await message.answer(f"❌ Ошибка при добавлении цены: {err_msg}")
    else:
        await message.answer(f"✅ Цена {price} руб. добавлена для товара (магазин ID: {shop_id}).")
    await state.clear()
    await message.answer("🏠 Главное меню:", reply_markup=main_menu_keyboard())


# ------------------- Обработчик ввода строки поиска -------------------
@router.message(PriceStates.waiting_for_report_search)
async def process_report_search(message: Message, state: FSMContext):
    raw = (message.text or "").strip()
    # Пустая строка трактуется как «все товары»
    search_text = " & ".join(f"{w}:*" for w in raw.split()) if raw else None
    await state.clear()
    await send_prices_report(message, message.from_user.id, search_text)


# ------------------- Кнопка «Все товары» -------------------
@router.callback_query(F.data == "report_all")
async def report_all(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    # Меняем сообщение, чтобы не висело
    await callback.message.edit_text("⏳ Формирую отчёт по всем товарам…")
    await send_prices_report(callback.message, callback.from_user.id, search_text=None)
    await callback.answer()


async def send_prices_report(message: Message, user_id: int, search_text: str | None = None):
    pool = await get_pool()
    html_content, err_msg = await crud.call_get_prices_report(pool, user_id, search_text)

    if err_msg or not html_content:
        await message.answer(
            f"❌ Ошибка при формировании отчёта: {err_msg or 'пустой результат'}",
            reply_markup=main_menu_keyboard()
        )
        return

    file_bytes = html_content.encode("utf-8")
    filename = f"prices_report_{datetime.now():%Y%m%d_%H%M%S}.html"
    document = BufferedInputFile(file_bytes, filename=filename)

    await message.answer_document(
        document,
        caption="📊 Отчёт по ценам сформирован.\nСкачайте файл и откройте в браузере.",
        reply_markup=main_menu_keyboard()   # меню остаётся и на документе — теперь безопасно
    )
    # Обновляем статусное сообщение (оно текстовое — правим без проблем)
    try:
        await message.edit_text("✅ Отчёт отправлен. Файл выше ⬆️", reply_markup=main_menu_keyboard())
    except TelegramBadRequest:
        pass


# ------------------- Обработчики ввода и сброса даты -------------------
@router.message(DateStates.waiting_for_date)
async def process_date_input(message: Message, state: FSMContext):
    raw = (message.text or "").strip()
    try:
        parsed = datetime.strptime(raw, "%d.%m.%Y").date()
    except ValueError:
        await message.answer(
            "❌ Неверный формат. Введите дату как <b>ДД.ММ.ГГГГ</b> "
            "(например: 15.08.2025):",
            reply_markup=date_keyboard(),
        )
        return

    pool = await get_pool()
    err = await crud.set_price_date(pool, message.from_user.id, parsed)
    await state.clear()

    if err:
        await message.answer(f"❌ Ошибка: {err}", reply_markup=main_menu_keyboard())
    else:
        await message.answer(
            f"✅ Дата <b>{parsed:%d.%m.%Y}</b> установлена.",
            reply_markup=main_menu_keyboard(),
        )


@router.callback_query(F.data == "date_reset")
async def date_reset(callback: CallbackQuery, state: FSMContext):
    pool = await get_pool()
    err = await crud.set_price_date(pool, callback.from_user.id, None)
    await state.clear()

    if err:
        await safe_edit(callback, f"❌ Ошибка: {err}", reply_markup=main_menu_keyboard())
    else:
        await safe_edit(
            callback,
            "✅ Дата сброшена. При вводе цен будет использоваться текущая дата.",
            reply_markup=main_menu_keyboard(),
        )
    await callback.answer()