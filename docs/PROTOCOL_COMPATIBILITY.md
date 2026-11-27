# Матриця сумісності протоколів Old Kraken

Цей документ фіксує підтверджену сумісність між історичними поколіннями аддона (`v0.3.3`–`0.5.8-alpha.2`) за результатами аудиту коду та автоматизованих Lua 5.1 тестів (`tests/test_protocol_compat_matrix.py`, `tests/test_workshop_orders_compat.py`, `tests/test_two_clients.py`).

Пороги й межі тут **не є активним compatibility gate** — це довідник фактичної поведінки протоколів перед будь-яким рішенням про відсікання старих версій.

---

## 1. Контрольні версії (Git refs)

| Версія / ref | Що змінювалося |
|---|---|
| `v0.3.3` | З аналізованих Lua-модулів наявні лише `Communication.lua`, `Core.lua`, `Database.lua`, `GuildRoster.lua`; тільки `TEST^`/`ACK^`, немає `VALID_TYPES`, `OKP^QUERY`/`OKP^HERE^<ver>`, GroupFinder, GuildEvents і Workshop. |
| `v0.4.0` | Поява `GF2^`, усіх 36 типів `VALID_TYPES`, `OKP^QUERY` / `OKP^HERE^<ver>`, GroupFinder, GuildEvents, Workshop (`WRQ` кожні 180 с). `WorkshopOrders` має 4 хвостові поля (без `rewardSilver`). |
| `v0.5.1`–`v0.5.2` | У `WorkshopOrders` додано 5-те хвостове поле `rewardSilver` (починаючи з `v0.5.1`). |
| `v0.5.4`–`v0.5.6` | Додано `OKP^SPEC^` і `OKP^SPEC2^` (починаючи з `v0.5.4`). `WRQ` усе ще кожні 180 с. |
| `0.5.7` (`origin/main`) | Збільшено інтервал `WRQ` з 180 с до 600 с. |
| `0.5.8-alpha.2` (`alpha`) | Переведення `WRGET`/`WRPAGE` на `WHISPER` для адресатів `>= 0.5.8-alpha.2` (`GUILD`-фолбек для старіших/невідомих/`self`), перевірка WHISPER-відправника за `GUILD`-присутністю, вилучення 6 збиральних/вторинних професій (`186, 182, 393, 185, 129, 356`). |

---

## 2. Матриця сумісності за рівнями

| Підсистема | Діапазон версій | Транспорт | Wire format | Обробка (handlers/decoders) | Функціональність і втрата даних |
|---|---|---|---|---|---|
| **Presence & Handshake**<br>`OKP^QUERY`, `OKP^HERE^<ver>`, `TEST^`/`ACK^` | `v0.3.3` ↔ `alpha`<br>`v0.4.0–0.5.7` ↔ `alpha` | `GUILD`<br>`GUILD` | Немає `OKP^HERE^<ver>`<br>Сумісно (`OKP^HERE^<ver>`) | `v0.3.3` ігнорує `OKP^QUERY`; `alpha` приймає `TEST^`<br>Повний двосторонній обмін | `v0.3.3` фіксується як presence з версією `nil` (`unknown`)<br>Повна ідентифікація версії |
| **Спеціалізації**<br>`OKP^SPEC^`, `OKP^SPEC2^` | `v0.4.0–v0.5.3` ↔ `alpha`<br>`v0.5.4–0.5.7` ↔ `alpha`<br>`alpha` ↔ `alpha` | `GUILD`<br>`GUILD`<br>`GUILD` | Не розпізнається<br>Сумісно<br>Сумісно | Старий клієнт безпечно ігнорує (`stats.invalid == 0`); `alpha` декодує старі пакети (у `v0.5.4+`)<br>Декодується в обидва боки | Спеки нового клієнта не показуються на `<= v0.5.3`<br>Повна (перевірено на wire/handler рівні) |
| **Group Finder**<br>`ANNOUNCE`, `JOIN`, `RESPONSE`, `UPDATE`, `CANCEL`, `QUERY`, `SYNC`, `BUMP` | `v0.4.0–0.5.7` ↔ `alpha` | `GUILD` | Сумісно (`unpackFields(..., 215)`) | Сумісно в обидва боки для `ANNOUNCE` ↔ `JOIN` | Двосторонній базовий обмін (`ANNOUNCE` ↔ `JOIN`); додаткові UI/фільтри та решта сценаріїв залежать від версії клієнта |
| **Guild Events**<br>`CEVENT`, `CVNEW`, `CVSTATE`, `CVCANCEL`, `CEVQUERY`, `CEVRSVP` | `v0.4.0–0.5.7` ↔ `alpha` | `GUILD` | Сумісно | Сумісно в обидва боки для `CEVENT` ↔ `CEVRSVP` | Двосторонній базовий обмін (`CEVENT` ↔ `CEVRSVP`); решта сценаріїв і UI-обмежень окремо не перевірялися |
| **Workshop (професії)**<br>`WKPROF`, `WKQUERY`, `WKRELAY` | `v0.4.0–0.5.7` ↔ `alpha` | `GUILD` | Сумісно | `alpha` відфільтровує 6 старих ID через `LEGACY_IGNORED_PROFESSIONS` | **Контрольована втрата даних** на `alpha` для 6 вилучених професій (`186,182,393,185,129,356`) |
| **Workshop Recipes**<br>`WRQUERY`, `WRRESULT`, `WRBATCH`, `WRLEARN`, `WRFORGET` | `v0.4.0–0.5.7` ↔ `alpha` | `GUILD` | Сумісно | `alpha` приймає 6 крафтових ID і відхиляє всі 6 вилучених ID у `validRecord()` | **Контрольована втрата даних** на `alpha` для `186,182,393,185,129,356` *(перевірено на рівні wire/handler для `WRLEARN`)* |
| **Workshop Sync**<br>`WRQ`, `WRIDX`, `WRGET`, `WRPAGE` | `v0.4.0–v0.5.6` ↔ `alpha`<br>`0.5.7` ↔ `alpha`<br>`alpha` ↔ `alpha` | `GUILD` (`WRQ` **180 с**)<br>`GUILD` (`WRQ` **600 с**)<br>`WRQ`/`WRIDX` → `GUILD` (**600 с**); `WRGET`/`WRPAGE` → **`WHISPER`** | Сумісно<br>Сумісно<br>Сумісно | Повний цикл `WRQ → WRIDX → WRGET → WRPAGE` працює з імпортом рецептів у store отримувача | Повна синхронізація крафтових рецептів; клієнти `< 0.5.8-alpha.2` генерують `GUILD`-трафік (`WRGET`/`WRPAGE` у `GUILD`) |
| **Workshop Orders**<br>`WORDER`, `WORELAY`, `WOREQ`, `WOPAY`, `WOERROR`, `WOQUERY`, `WOACT`, `WOPAYR`, `WORESULT`, `WORESR` | `v0.4.0` ↔ `alpha`<br>`v0.5.1–0.5.7` ↔ `alpha` | `GUILD`<br>`GUILD` | `v0.4.0`: 4 хвостові поля; `v0.5.1+`/`alpha`: 5 хвостових полів (`rewardSilver`)<br>Сумісно | **`alpha → v0.4.0`: відхиляється** декодером `v0.4.0` (навіть при `rewardSilver = 0`); **`v0.4.0 → alpha`: приймається** (`rewardSilver = 0`)<br>Сумісно в обидва боки | **Несумісність `alpha → v0.4.0`** для створення замовлень на стороні `v0.4.0`; на `alpha` також відхиляються замовлення зі старих клієнтів для вилучених професій (`185, 129, 186`) |

---

## 3. Важливі транспортні й безпекові властивості `0.5.8-alpha.2+`

- **WHISPER-маршрутизація (`WRGET`, `WRPAGE`):** активується лише тоді, коли `GetRosterVersion(target) >= 0.5.8-alpha.2` і `target` не є поточним персонажем. Для `unknown` (`nil`), старіших версій або `self` використовується `GUILD`.
- **Валідація WHISPER-відправника:** `Communication:OnAddonMessage` приймає `WHISPER` лише для `GF2^` з `UNICAST_KINDS` (`WRGET`, `WRPAGE`) і лише якщо відправник уже має підтверджену `GUILD`-присутність у поточній гільдії (`HasRosterAddon(sender)` і `presenceGuild ~= ''`), до виклику `receiveAddonMessage()`.
- **Фактор `GUILD`-навантаження:** клієнти `v0.4.0–v0.5.6` опитують `WRQ` кожні 180 с (у 3,3 рази частіше за `0.5.7+`), а будь-який клієнт `< 0.5.8-alpha.2` примушує обмін `WRGET`/`WRPAGE` із ним іти через широкомовний `GUILD`.

---

## 4. Межі доказовості тестів

- Усі перевірки сумісності виконано в ізольованому Lua 5.1 середовищі (`Lupa`) з реальними файлами з Git (`v0.3.3`, `v0.4.0`, `v0.5.2`, `v0.5.4`, `v0.5.6`, `origin/main` = `0.5.7`, `HEAD` = `0.5.8-alpha.2`).
- `test_protocol_compat_matrix.py`:
  - перевіряє `WRQ` cadence за часовими межами (`+165/+185` і `+585/+605`), що доводить умови інтервалів у `WorkshopSync`, але не симулює реальний 3-секундний `C_Timer.NewTicker` у WoW-клієнті;
  - перевіряє `OKP^SPEC2^` та `WRLEARN` на рівні wire/handler (без UI/scanner encoder і без реальної фрагментації `Communication` для `SPEC2`);
  - перевіряє повний цикл `WorkshopSync` (`WRQ → WRIDX → WRGET → WRPAGE`) включно з імпортом рецепта в store отримувача, а також окремо `WHISPER` для `alpha ↔ alpha`.
- `test_workshop_orders_compat.py`:
  - ізолює `encode()`/`decode()` і handler `WorkshopOrders` на реальних файлах `v0.4.0`, `0.5.7` і `alpha` (зі stub-транспортом замість повного `Communication`), включно з `rewardSilver = 0` та `50`.
