# AGENTS.md — правила роботи з Old Kraken (гілка `alpha`)

Інструкції для AI-агентів (OpenCode, Codex, Copilot, Antigravity, Gemini CLI, Claude Code) у цьому репозиторії.
Файл **не дублює** `README.md` і `TESTING.md` — він фіксує те, що агент мусить знати, щоб не ламати аддон і не вигадувати API.

> **Цей файл описує актуальний стан коду (`0.5.3-alpha.1` у `alpha`, `0.5.2` у `main`).** Обидві гілки містять повну 17-файлову структуру аддона, схема БД v3.
>
> **Посилання тут — на імена функцій, констант і розділів, а не на номери рядків.** Гілка `alpha` рухається швидко, тож номери рядків застарівають. Шукай за символом: `grep -rn "ReceiveGroup" --include="*.lua" .`

---

## 1. Що це і для чого

Аддон WoW на Lua для україномовної гільдії: реєстр гільдії, Group Finder (пошук групи), гільдійний календар подій, «майстерня» (професії, рецепти, замовлення на крафт).

- **Цільовий клієнт:** WoW Forever `1.60.1 (70938)`, `## Interface: 16001`. Retail/Classic **не цільові** — не додавай гілки «для сумісності», якщо про це не просили.
- **Runtime:** **Lua 5.1**. Заборонено: `goto`, `continue`, побітові оператори (`&`, `|`, `<<`, `>>`, `~`), `//`, `table.pack`/`table.unpack` (тільки `unpack`), `#`-оператор на nil-таблицях, конструкції з 5.2+.
- Доступні хелпери WoW: `strsplit`, `strjoin`, `tinsert`, `tremove`, `wipe`, `format`, `pcall`, `C_Timer.After/NewTicker`, `GetTime`, `GetServerTime`, `hooksecurefunc`.
- **Без XML** — весь UI будується кодом. **Без зовнішніх бібліотек** (жодного LibStub/Ace3). **Без `TODO`/`FIXME`/`XXX`/`HACK`** — їх у репо немає ніде (ні `.lua`, ні `.py`, `.md`, `.yml`); обмеження описані прозою в коментарях і документації. Не додавай цих маркерів — пиши пояснення коментарем.
- **Мова:** українська за замовчуванням, англійська через налаштування. Для нового тексту інтерфейсу додавай англійський відповідник у `Locale.lua`. Коментарі, ідентифікатори й назви функцій — англійською.

### Розмір коду

17 Lua-файлів, 11 962 рядки. Найбільші: `GroupFinderUI.lua` (2361), `GuildEvents.lua` (1453), `WorkshopRecipes.lua` (1317), `WorkshopOrders.lua` (1276), `Core.lua` (1186), `GuildRoster.lua` (1021).

---

## 2. Три робочі копії одного репо (перевіряй, де ти)

`https://github.com/Noxter/old-kraken-addon.git` має щонайменше три checkout-и на цій машині:

| Шлях | Гілка / стан | Призначення |
|---|---|---|
| `~/Projects/old-kraken-alpha/` | `alpha` (ця копія) | **актуальна розробка (`0.5.3-alpha.1`)** |
| `~/Projects/old-kraken-addon/` | `main` | **релізна гілка (`0.5.2`)** |
| `~/Projects/copilot-worktrees/old-kraken-addon/copilot-prewarm-fluffy-winner` | detached worktree | службовий |

**Перед початком роботи завжди:** `git status -sb` + `git log --oneline -1` у `old-kraken-alpha`. Не роби `git reset --hard`, `git checkout .`, `git stash` без підтвердження користувача.

---

## 3. Порядок завантаження (`OldKraken.toc`) — критично

`OldKraken.toc` вантажить файли **строго** в цьому порядку:

```
Database.lua          Locale.lua          Core.lua            UIHub.lua
Communication.lua     GuildRoster.lua     ActivityCatalog.lua
GroupFinder.lua       GroupFinderIntegration.lua   GroupFinderUI.lua
GroupFinderAPI.lua    GuildEvents.lua     Workshop.lua
WorkshopRecipes.lua   WorkshopSync.lua    WorkshopOrders.lua
WorkshopDeliveries.lua  Minimap.lua
```

Наслідки, які не можна порушувати:

- **`OldKraken.DB` існує лише після `Database.Initialize()`**, який викликається з `Core.lua` на `ADDON_LOADED`. Кожен модуль у `connect()` **перевіряє `OldKraken.DB` на nil** і мовчки деактивується, якщо його немає. Не прибирай ці перевірки.
- Модулі, що реєструють обробники, роблять це **на file scope** (`RegisterHandler` одразу при завантаженні файлу). `Communication.lua` вантажиться **раніше** за всіх, хто реєструє обробники — тому зміна семантики `RegisterHandler` або `VALID_TYPES` зачіпає **усі** модулі.
- `WorkshopDeliveries.lua` на file scope робить `local orders = OldKraken.WorkshopOrders` → **мусить вантажитися після `WorkshopOrders.lua`**.
- `UIHub.lua` вантажиться **до** сторінок: кожна сторінка реєструється через `UIHub:RegisterPage(key, title, shortcut, create)` на file scope, і **порядок реєстрації = порядок вкладок**.
- `ActivityCatalog.lua` вантажиться до `GuildEvents.lua` і `GroupFinderUI.lua`, які читають його на file scope.
- **Файли, які додаєш у `OldKraken.toc`, мають існувати** — CI (`validate-pr.yml`) і обидва packaging-воркфлоу парсять TOC через `awk` і падають, якщо файлу немає.

---

## 4. Конвенції коду

- **Простори імен:** один глобальний `OldKraken`. Кожен модуль — `OldKraken.X` (`OldKraken.GuildEvents`, `OldKraken.Workshop`, …). Локальні змінні модуля — `local X = {}` на початку файлу. Не створюй нових глобалів.
- **Події всередині аддона:** `OldKraken:On(name, fn)` / `OldKraken:Fire(name, ...)` (у `Core.lua`). Не використовуй `CreateFrame`+`OnEvent` для внутрішніх подій.
- **UI:** усі контроли — через `OldKraken.UIStyle`:
  - `UIStyle.Window(frame)`, `UIStyle.Button(...)`, `UIStyle.Input(...)`, `UIStyle.Dropdown(...)`, `UIStyle.Panel(...)`, `UIStyle.Colors`, `UIStyle.EmblemPath()`.
  - `UIStyle.Dropdown` вимагає **іменованого** фрейму (він реєструє його у `UIDropDownMenu_*`). Безымянний фрейм зламає дропдаун.
  - Палітра: фон `0.025,0.035,0.055`, панель `0.055,0.07,0.095`, золото `0.88,0.69,0.32`, синя кнопка `0.30,0.37,0.83`.
- **Чат:** префікс інформації — `|cff2ec4b6Old Kraken|r:`, помилки — `|cffff5555`.
- **Медіа:** шляхи **жорстко** вигляду `Interface\AddOns\OldKraken\Media\...` — прив'язані до **назви теки `OldKraken`**, а не до `OldKraken.name`. `UIStyle.EmblemPath()` використовує `OldKraken.name` (правильно), але в `ActivityCatalog.SetArtwork` шлях складено через `OldKraken.name` — якщо перейменуєш теку аддона, зламається все. Файли в `Media/`: `OldKrakenKraken.tga`, `OldKrakenEmblem.tga`, `RoleSlot.tga`, `StatusOnline.tga`, `StatusOffline.tga`, `Media/Raids/*.tga`.
- **Стиль:** густий, компактний Lua — багато однорядкових `if ... then return end`. Тримайся наявного стилю файлу, який редагуєш, не «покращуй» форматування сусідніх рядків.
- **Помилки:** модулі здебільшого повертають `nil`/`false` **без повідомлення користувачу** (тиха відмова валідації). Діагностика — через `/okr comm status` і `/run`-хелпери, а не через UI-помилки.

---

## 5. SavedVariables і схема БД

`## SavedVariables: OldKrakenDB` — один глобальний SavedVariables, `OldKraken.DB` — живий хендл.

**`SCHEMA_VERSION = 3`** у `Database.lua` (у гілці — незакомічена зміна з 2 на 3).

Міграції **адитивні й послідовні** (`schemaVersion < N`), виконуються в порядку 1 → 2 → 3:

| Порог | Що додає |
|---|---|
| `< 1` | `settings`, `roster`, `events` |
| `< 2` | `groupFinder` |
| `< 3` | `workshop` |

Правила:
- **Ніколи не видаляй і не перейменовуй поля** в міграціях — «Schema migrations must preserve existing SavedVariables wherever possible». Додавай `EnsureTable` для нової секції + новий `schemaVersion`.
- Якщо `schemaVersion > SCHEMA_VERSION` (файл з новішого білда) — БД **не чіпається**, повертається як є. Не «нормалізуй» її.
- Після міграцій завжди `EnsureTable` для всіх секцій + `ApplyDefaults(db, DEFAULTS)` + `NormalizeRosterSettings` + `db.version = OldKraken.version`.
- Додаючи секцію — онови **три** місця: `DEFAULTS`, міграційний `if schemaVersion < N`, і `EnsureTable` у хвості `Initialize()`. Плюс `tests/test_database.py` і `TESTING.md`.

### Простори імен (усе скомпільовано під realm+guild)

| Дані | Ключ | Місце |
|---|---|---|
| Події | `realm..'\001'..guild..'\001'..name` (**на персонажа**) | `DB.events.guildCalendarV1[key]` |
| Майстерня (професії, рецепти, синк, замовлення) | `realm..'\001'..guild` (**спільний на гільдію**) | `DB.workshop.guilds[key]` |
| Глобальний кеш рецептів | — | `DB.workshop.recipeCatalog` |
| Group Finder | `realm..'\001'..guild..'\001'..name` | `DB.groupFinder[key]` |
| Налаштування | — | `DB.settings.*` |

**Важливо:** `Workshop`, `WorkshopRecipes`, `WorkshopSync`, `WorkshopOrders` пишуть в **той самий** `workshop.guilds[key]` — це один спільний скоуп. Додаючи поле, використовуй унікальний префікс (наявні: `records`, `recipes`, `recipe*`, `order*`, `pending*`), щоб не зіткнутися.

### Ключі `DB.settings`

`roster` (`status` = `all|online|offline`, `sort` = `name|level|class|rank|zone`, `ascending` bool, `class`, `search`), `minimapAngle`, `alertPositions`, `groupFinderNotifications`, `guildEventNotifications`, `workshopOrderAlerts`.

`NormalizeRosterSettings` **жорстко** валідує `status`/`sort`/`ascending`/`class`/`search`. Додаєш новий ключ у `settings.roster` — додай і нормалізацію.

---

## 6. Транспорт: `Communication.lua`

Уся міжклієнтська комунікація йде **тільки** через гільдійний канал (`'GUILD'`). Жодних `PARTY`/`RAID`/`WHISPER`/`CHANNEL`.

### Кадр

- Префікс: **`OLDKRKN`** (`PREFIX`), реєструється один раз на `PLAYER_LOGIN` через `C_ChatInfo.RegisterAddonMessagePrefix`.
- Формат: **`GF2^KIND^ID^PART^COUNT^HEX`** (розділювач `^`).
- `ID` = `sessionID..'-'..messageSequence`, де `sessionID = GetServerTime()..'-'..random(100000,999999)`. На прийомі `#id <= 32`.
- `HEX` — кожен байт payload як `%02X`. Це зберігає UTF-8 і звільняє розділювачі.
- **Коментар у `Encode` каже «GF1 payloads…» — це помилка формулювання**, тег кадру — `GF2`. Не вирівнюй код під коментар.

### Ліміти

| Ліміт | Значення | Де |
|---|---|---|
| Байтів на частину (`PART_BYTES`) | 80 | const |
| Частин на передачу (`MAX_PARTS`) | 32 | const |
| Payload на передачу | **2560 B** (80×32) | `SendProtocol` + прийом + `_unpackFields` |
| Цілий кадр | **240 B** | send / enqueue / receive |
| Sender-рядок | 128 B | прийом (тихо дропає, **без** `invalid++`) |
| Рядок версії presence | 48 B | прийом |
| `MAX_QUEUE` | 4096 | const |
| `ACTION_RESERVE` | 256 | const |
| `BACKGROUND_LIMIT` | 3584 (queue − reserve) | const |
| `MAX_ASSEMBLIES` | 1024 одночасних збірок | const |
| `CACHE_LIMIT` / `CACHE_TTL` | 4096 / 120 с | const |

**Обмеження `#payload > PART_BYTES*MAX_PARTS` — 2560 B.** Будь-який новий тип повідомлення мусить уміщатися; інакше розбивай на сторінки (як `WRPAGE`) або скорочуй (як `fits()` у `WorkshopOrders`, що перевіряє `≤2560` перед відправкою).

### Пріоритети й черга

- Пріоритети (`PRIORITY`): **0** — дії (`JOIN`, `RESPONSE`, `CANCEL`, `CEVRSVP`, `CVCANCEL`, `WOREQ`, `WOACT`, `WOPAY`, `WOPAYR`, `WORESULT`, `WORESR`); **1** — знімки (`ANNOUNCE`, `UPDATE`, `BUMP`, `WORDER`, `CVNEW`, `CVSTATE`, `CEVENT`); **2** — решта.
- `Pump` (тікер **0,7 с**) бере найменший пріоритет, `break` на 0.
- **Правило порядку: «знімок ніколи не має обганяти рішення, яке на нього посилається»** — `GROUP_SNAPSHOTS = {ANNOUNCE, UPDATE, SYNC, CANCEL, BUMP}` переставляються перед рішенням через `job.recordKey` (перші два запакованих поля). Не ламай це.
- Черга обмежена: пріоритет 0 → до `MAX_QUEUE`, інакше до `BACKGROUND_LIMIT`. Переповнення → `stats.backpressure++`, `false, 'queue full'`.
- **Дедуп:** `pendingTransmissions[guild\001kind\001payload]` — повторна постановка того самого payload повертає наявний id.
- **Backoff:** при невдачі `backoff = min(60, backoff==0 and 2 or backoff*2)` + джиттер. **Ліміту спроб немає** — повтори нескінченні. (`README.md` у розділі про чергу каже «обмеження 50 … не більше п'яти спроб» — застаріло.)
- **Replay multipart:** якщо передача триває ≥ **90 с** — усі частини знімаються, `startedAt` скидається, повний набір ставиться в чергу знову (`stats.restarted++`).
- **Тротлінг на боці виклику:** модулі ставлять у чергу лише коли `#comm.queue <= 8` (перевіряй це у своєму коді, якщо додаєш новий масовий відправник).

### Прийом

- Ключ збірки — `sender .. '\001' .. id`.
- Валідація: regex кадру, відомий kind, `#id ≤ 32`, `count` ∈ 1..32, `part` ∈ 1..count, декодований payload, `#payload ≤ 80`, не-остання частина рівно 80.
- Розбіжність kind/count між частинами → збірка відкидається. Конфліктна дубльована частина → відкидається. Завершений id, що прийшов знову → ігнорується.
- Обробник викликається під `pcall`; помилка → `stats.invalid++` + повідомлення в чат. **Один зламаний обробник не має валити інші** — не прибирай `pcall`.

### Типи повідомлень: закритий whitelist

`VALID_TYPES` — **закритий перелік**; `RegisterHandler` відхиляє невідомий kind, нефункцію і дублікат. **37 типів.**

Додаєш новий тип — обов'язково:
1. дописати в `VALID_TYPES`;
2. зареєструвати обробник у своєму модулі (на file scope);
3. додати в `PRIORITY`, якщо це дія або знімок;
4. задокументувати порядок полів payload (див. нижче).

Порядок полів за модулями (payload — вивід `_pack`, якщо не вказано інше):

- **Group Finder** (`GroupFinderIntegration`): `ANNOUNCE`/`UPDATE`/`SYNC`/`CANCEL`/`BUMP` → `EncodeGroup`; `JOIN` → `applicationFields`; `RESPONSE` → `{owner,id,applicant,decision,version}`; `QUERY` → `""`.
- **Guild Events**: `CEVENT`/`CVNEW`/`CVCANCEL`/`CVSTATE` → `encode(e)` = `{id,owner,rev,when,kind,size,cancelled,title,description,n,(name,role)×n,activity,statusCodes}` (maxFields 212); `CEVRSVP` → `{owner,id,role,version[,roleCode]}`; `CEVQUERY` → `""`.
- **Workshop (професії)**: `WKPROF` → `{timestamp,n,(id,rank,maximum)×n}` (maxFields 38); `WKRELAY` → `{owner,professionPayload}`; `WKQUERY` → `""`.
- **Workshop (рецепти)**: `WRQUERY` → `{token,query}`; `WRBATCH` → `{sender,token,rows…}` (maxFields 98); `WRRESULT` → 8 полів; `WRLEARN`/`WRFORGET` → 6 полів.
- **Workshop (синк)**: `WRQ` → `""`; `WRIDX` → `{target,owner,rev,count}`; `WRGET` → `{provider,owner,rev}`; `WRPAGE` → `{target,owner,rev,part,total,rows…}` (maxFields 117).
- **Workshop (замовлення)**: `WORDER`/`WORELAY` → `encode(o)` (maxFields 80); `WOREQ` → `{owner,id,action,version,assignment}`; `WOPAY` → `{owner,id,assignment,amount}`; `WOERROR` → 5 полів; `WOQUERY` → `""`; `WORESULT`/`WORESR` → 8 полів. **`WOACT` і `WOPAYR` — свідомо порожні заглушки** (релейник не може довести особу актора).

### Кодек

`GroupFinder.lua` експортує `_pack(fields)` і `_unpackFields(payload, maxFields)`:

- `_pack` — конкатенація `#value .. ':' .. value` для кожного поля.
- `_unpackFields` — відкидає `#payload > 2560`, довжину-префікс понад 4 цифри, і перевищення `maxFields`.
- **Кодек використовують не лише Group Finder:** `GuildEvents`, `Workshop*`, `WorkshopSync`. Зміна сигнатури `_pack`/`_unpackFields` ламає **всі** вони.
- Обмеження «≤ 4 цифри» означає, що будь-яке поле довжиною > 9999 символів зламає кодек. Тримай поля короткими.

### Версіонування

- **Протокол не має поля версії.** Немає ні в кадрі, ні в payload. Є лише per-record лічильники (`rev`, `version`, `requestSequence`), які версіонують **дані**, не протокол.
- Єдина версія «на дроті» — рядок версії аддона в `OKP^HERE^<version>` (валідація `^[%w%.%+%-]+$`, ≤ 48 символів), який зберігається як presence у реєстрі.
- Тому **сумісність між клієнтами різних версій не гарантована** — узгоджуй зміни форматів уручну. Нові поля додавай **тільки в кінець** payload, щоб старі клієнти хоч частково читали.

### Legacy / presence (не `GF2`)

`TEST^id^name^name`, `ACK^id^target^me`, `OKP^QUERY`, `OKP^HERE^<version>` — розбираються через `strsplit("^")`.

### Ідентичність — найризикованіше місце

- **`Ambiguate` не використовується ніде.** `normalizeSender` повертає sender **без змін**.
- Приймачі порівнюють **сирий рядок sender** з owner/identity з payload: `sender ~= owner` у `ReceiveGroup`/`ReceiveJoin`/`ReceiveResponse` (`GroupFinder.lua`), `receiveEvent` (`GuildEvents.lua`), декодері замовлень (`WorkshopOrders.lua`), `Workshop.lua` тощо.
- На клієнті Forever `UnitName('player')` повертає **ім'я + прізвище**, а GUILD-sender несе обидва через пробіл. Тому `GroupFinderIntegration.playerIdentity` склеює `name .. " " .. surname`.
- **`PresenceKey`** додає `-<realm>` лише якщо в імені **немає** дефіса, і вирізає всі пробіли: `"Ivan"` → `"Ivan-Realm"`, `"Ivan Surname"` → `"IvanSurname-Realm"`. Це не те саме, що identity у Group Finder — **не змішуй ці дві форми**.
- Presence — **доказ встановлення в цій сесії, ніколи не доказ відсутності**. Скидається при зміні гільдії.
- Якщо чіпаєш ідентичність — перевір **усі** місця порівняння sender і `tests/test_integration.py` (там є тести на форж sender'а і близнюків з однаковим ім'ям).

### Команди транспорту

`/okr comm status` → `PrintStatus()` (українською: доступність API, префікс, обмеження, гільдія, черга, retry, `deduplicated`/`backpressure`, `sent`/`retried`/`dropped`/`invalid`).
`/okr comm test` → `SendTest()` — ставить `TEST^…` у чергу.

---

## 7. Group Finder

Файли: `GroupFinder.lua` (модель + кодек + LFG-probe), `GroupFinderIntegration.lua` (транспорт/синк), `GroupFinderUI.lua` (UI), `GroupFinderAPI.lua` (нативний API probe).

- **Авторитет власника:** `ReceiveGroup` приймає зміни **лише** якщо `sender == owner`. `ReceiveJoin` вимагає, щоб заявник був тим, ким назвався; `ReceiveResponse` приймає `sender == owner`.
- **`RESPONSE` несе лише `'reject'`** — рішення «прийнято» передається через сам знімок групи (змінений склад), а не окремим повідомленням. Не додавай `'accept'` у `RESPONSE`, не переробивши всю логіку.
- **`ReceiveGroup` сумісний з 12/13/14/15 полями** + `count` — нові поля додавай у кінець, старі формати мусять читатися.
- **ID групи містить `GetServerTime()`** — тому вік групи обмежений, а `reannounce` має кулдаун **300 с** (тестується на межах 299/300).
- **`requestVersions` — monotonic fence:** стара заявка/рішення не може перезаписати новішу. Тест `tests/test_group_replay.py` перевіряє, що fence переживає рестарт.
- Ліміти: `MAX_GROUPS = 100`, `GROUP_TTL = 3600`.
- Ролі беруться з `UnitGetAvailableRoles`/`C_LFGList.GetAvailableRoles` — **ніколи** з таблиці класів (`tests/test_class_roles.py` це фіксує).
- LFG-probe **read-only**: `C_LFGList`/`C_LFGInfo` лише читаються, `Search`/`CreateListing`/`UpdateListing` не викликаються.
- Періодичний `QUERY` (синк) + `RequestSync()`; `ClearProtocolState()` викликається при деактивації інтеграції.

---

## 8. Guild Events (гільдійний календар)

`GuildEvents.lua` (1020 рядків).

- **Relay authority — головне правило.** Подію може змінювати **лише власник**. Релейні копії — **display-only**: вони не анонсують, не скасовують, не приймають заявки.
  - `canJoin = not e.relayed and …` — на релейну подію **не можна записатися**.
  - Релейне скасування **не** породжує сповіщення і збільшує `rejected_relay_cancelled`.
  - Новіша **пряма** копія завжди перемагає релейну, навіть якщо в релейної вищий `rev`.
  - Спроба видати себе за прямого sender'а → `invalid_payload`.
  - **`tests/test_events_relay_authority.py` — інертний** (див. §13): він містить 5 таких тестів, але жоден не виконується під `python tests/test_events_relay_authority.py`. Тобто ці інваріанти **фактично не захищені CI**. Якщо чіпаєш relay-логіку — перевіряй уручну за розділами `TESTING.md` «Guild Events: перевірка авторитетності relay» та «Ручний тест relay у Guild Events (A — автор, B — прямий отримувач, C — отримувач через B)».
- Зберігання: `DB.events.guildCalendarV1[key]` — `owned`, `observed`, `intents`, `sequence`, `cancelledSeen`, `relays`.
- Дедуп/anti-replay: монотонний `rev` на власника + виявлення еквівалентності повторним кодуванням і порівнянням payload; `cancelledSeen` — томбстоуни.
- Ліміти: **≤ 100 живих подій**; prune через **172800 с**; ≤ 100 учасників, ≤ 200 записів версій; title ≤ 100, description ≤ 400; `when` — у майбутньому і ≤ 1 рік; розмір 2–40.
- Ролі: `tank`/`healer`/`dps`/`flex`. Статуси: `pending`/`accepted`/`reserve`/`rejected`. Типи: `raid`/`dungeon`/`pvp`/`guild`.
- **Рольова здатність** кодується 3-бітним рядком `^[01][01][01]$` (`RoleCapabilityCode`). `UnitGroupRolesAssigned` **не використовується ніде** — не вводь його.
- Запрошення: `C_PartyInfo.InviteUnit`, `C_PartyInfo.ConvertToRaid`, під гейтами `UnitIsGroupLeader`/`UnitIsGroupAssistant` + `InCombatLockdown`. Памп 0,8 с в `OnUpdate`, перезапуск по `GROUP_ROSTER_UPDATE`. Пакет `raidInvites` спливає через 300 с.
- Каденс: `CEVQUERY` кожні 180 с, одна «брудна» подія на тік, релей пересилається поки `#comm.queue <= 8`.
- **Діагностика:** `/run OldKraken.GuildEvents:PrintRelayDiagnostics()` (є також `GetRelayDiagnostics()`).
- **Відома вада:** `InviteAll` у `GuildEvents.lua` — у тілі методу є рядки (одразу після `local e=events[key]`), які звертаються до **невизначених** `window` і `selected`; видно за збитим відступом. Це залишок від копіпасти з UI-коду, може кидати nil-index. Не «виправляй» наосліп: спершу з'ясуй, чи метод взагалі викликається, і покрий тестом (`tests/test_event_raid_invites.py` поруч).

---

## 9. Майстерня (Workshop)

П'ять файлів, **два з них без публічного API**:

| Файл | Роль | Експорт |
|---|---|---|
| `Workshop.lua` | довідник професій, `WKPROF`/`WKRELAY`/`WKQUERY` | `OldKraken.Workshop` |
| `WorkshopRecipes.lua` | індекс/пошук рецептів, `WRQUERY`/`WRBATCH`/`WRRESULT`/`WRLEARN`/`WRFORGET` | `OldKraken.WorkshopRecipes` |
| `WorkshopSync.lua` | версійовані знімки рецептів, `WRQ`/`WRIDX`/`WRGET`/`WRPAGE` | **нічого** |
| `WorkshopOrders.lua` | стан-машина замовлень, `WORDER`/`WOREQ`/`WOPAY`/`WORESULT`/`WOERROR`/`WOQUERY` | `OldKraken.WorkshopOrders` |
| `WorkshopDeliveries.lua` | пасивне спостереження трейду/пошти | **нічого** |

- **DB-скоуп:** усі чотири стани пишуть у `DB.workshop.guilds[realm\001guild]`; `recipeCatalog` — глобальний кеш.
- **Залежності (напрям):** `Workshop` → `WorkshopRecipes`/`WorkshopOrders`; `WorkshopOrders` → `Workshop`/`WorkshopRecipes`; `WorkshopSync` → `Communication`/кодек/`WorkshopRecipes`; `WorkshopDeliveries` → **лише** `WorkshopOrders:RecordExchange`. Не роби циклічних викликів на file scope.
- **`WorkshopDeliveries` — це хук трейду/пошти, а не модуль.** Він:
  - **ніколи не ініціює** трейд чи лист («Observe confirmed trade and mail transfers; never initiate a trade or mail action»);
  - хукає `SendMail`, `TakeInboxItem`, `TakeInboxMoney`, `AutoLootMailItem` через `hooksecurefunc`;
  - слухає 14 подій (`TRADE_*`, `UI_INFO_MESSAGE`, `UI_ERROR_MESSAGE`, `MAIL_*`, `PLAYER_LEAVING_WORLD`);
  - викликає `RecordExchange` **лише** на підтвердженому завершенні; не підтверджені поштові записи молодші 5 с переставляються в чергу як retryable;
  - **не створює `OldKraken.WorkshopDeliveries`** — не намагайся його «викликати».
- **Синк: лише прямі знімки.** `recipeDirectSnapshots[owner]` зберігає тільки те, що прийшло **безпосередньо** від власника; релейні копії живуть у `recipeSnapshotViews` з `relayed=true` і ніколи не перепромінюються як авторитетні. Наслідок: якщо власник офлайн — ніхто не може віддати його знімок.
- **Future-date fence:** `WRIDX` відкидає `rev > GetServerTime()*1000 + 600000` — клієнт з кривим годинником не публікує.
- **Індекс рецептів асинхронний:** `ensureRecipeIndex()` обробляє по 200 записів на `C_Timer.After`-слайс і стріляє `WORKSHOP_INDEX_CHANGED`. Результати обмежені 500 (5000 для `prof:<n>`). **Відфільтрований скан не вважається повним** — не трактуй результати пошуку як вичерпні.
- Ліміти: професії — decode 38 полів, ≤ 12 професій на запис; рецепти — 1000 власників, 5000 записів/власник, каталог ≤ 10000, `sendQueue` ≤ 100 (TTL `WRLEARN` 120 с / `WRFORGET` 600 с); замовлення — 100 своїх + 100 спостережуваних, 20 кандидатів/ack, `RELAY_LIMIT = 1000`, `RELAY_TTL = 2592000`; синк — 2000 індексів, 8 одночасних вхідних, 10 задач, 60 с per-sender rate, чанк ≤ 112 полів і ≤ 2300 байт.
- **`WOACT`/`WOPAYR` — свідомі no-op** (релейник не доведе особу). Не «дописуй» їм логіку.
- `orderActionRelays`/`orderPaymentRelays` **стираються на кожному `connect()`** — вони транзитні, не персистяться між релоадами.
- Каденс: `WOQUERY` кожні 180 с, `WRQ` кожні 180 с.
- **UI:** `Workshop:SetView('professions'|'recipes'|'orders'|'orderCreate')`, `Navigate`/`Back`/`Show`; `Workshop.navigationStack` і `Workshop.currentView` скидаються на `connect()`.

---

## 10. Ростер, Minimap, UIHub, ActivityCatalog

### UIHub

- `UIHub:RegisterPage(key, title, shortcut, create)` — реєстрація **на file scope**, порядок = порядок TOC.
- Сторінки: `roster` (`GuildRoster.lua`), `groups` (`GroupFinderUI.lua`), `events` (`GuildEvents.lua`), `workshop` (`Workshop.lua`) — кожна реєструється викликом `UIHub:RegisterPage` на file scope свого файлу.
- Головне вікно: `OldKrakenHubFrame` 1140×660, у `UISpecialFrames` (закривається по Esc).
- Сторінки створюються **ліниво** (при першому показі). Бренд-марка 52×52, лінійка 884 px.

### Ростер (`GuildRoster.lua`)

- Фільтри: статус, клас, рівень, пошук. Сортування: `name|level|class|rank|zone`.
- **Сортування за локацією — регістронезалежне** (попри те, що каже `README.md`).
- Addon-фільтр ростера **не персиститься**.
- Кнопки «Оновити» в ростері **не існує** (розділ про ростер у `README.md` помиляється); оновлення — через `/okr refresh`.
- Пулінг рядків: 500 членів → ≤ 21 рядок; події ростера коалесцуються; скан професій — чанки по 25.
- Це ж файл-хост команд `/okr` (див. §11).

### Minimap (`Minimap.lua`, 66 рядків)

Кнопка аддона на мінікарті; кут зберігається в `DB.settings.minimapAngle`.

### ActivityCatalog (`ActivityCatalog.lua`, 66 рядків)

Єдине джерело істини для назв і арту підземель/рейдів.

- 28 підземель + порожній варіант «Усі / не вибрано»; 3 рейди (`barrowdeeps`, `hyjalsummit`, `onyxia`), усі `min=max=60`.
- `SetArtwork(texture, activity)`: рейди — з `Media/Raids/<Name>.tga`; решта — за fileID з fallback `7963779`. Для fileID ≥ 7000000 інший `SetTexCoord`.
- `validActivity` у `GuildEvents` **виводиться з каталогу** — додаючи активність, онови лише каталог + (за потреби) мапінг арту.

---

## 11. Команди `/okr`

Реєструються **один раз** — у `GuildRoster.lua` (`SLASH_OLDKRAKEN1`, `SLASH_OLDKRAKEN2`, `SlashCmdList["OLDKRAKEN"]`). Жоден інший файл не реєструє `SLASH_*`.

```
SLASH_OLDKRAKEN1 = "/okr"        SLASH_OLDKRAKEN2 = "/oldkraken"
```

Команда спершу **lower-case**, тож матчинг регістронезалежний.

Порядок диспетчеризації:

1. `OldKraken.Communication:HandleCommand(command)` — `comm status`, `comm test`. Повертає `true` → вихід.
2. `OldKraken.GroupFinderAPI:HandleCommand(command)` — лише `group api`.
3. Локальні підкоманди: `recipes`, `orders`, `workshop`|`craft`, `events`|`calendar`, `alerts group|request|event|workshop`, `group status`, `group sync`, `group`|`groups`.
4. Фолбеки: `refresh` → `Roster:RequestUpdate()`; **будь-яка невідома команда → відкриває ростер**.

**Немає help-виводу.** Невідома команда тихо відкриває ростер. Якщо додаєш підкоманду — вписуй її **перед** фолбеком `else` і пам'ятай, що `Communication` перевіряється першим (не називай підкоманду `comm …`, якщо не хочеш перехоплення).

---

## 12. Внутрішня шина подій

`OldKraken:On` / `OldKraken:Fire`. 16 імен + `INITIALIZED`:

```
GROUP_FINDER_CHANGED            GROUP_FINDER_NEW              GROUP_FINDER_NEW_REQUEST
GROUP_FINDER_APPLICATION_STATUS GROUP_FINDER_ALERT_SETTING    GUILD_EVENTS_CHANGED
GUILD_EVENTS_NEW                GUILD_EVENTS_NEW_SIGNUP       GUILD_EVENTS_CANCELLED
GUILD_EVENTS_ALERT_SETTING      ROSTER_ADDON_CHANGED          WORKSHOP_INDEX_CHANGED
WORKSHOP_ITEM_DATA_CHANGED      WORKSHOP_ORDER_NOTICE         WORKSHOP_PROFESSIONS_CHANGED
WORKSHOP_RECIPES_CHANGED        INITIALIZED
```

Додаючи нову подію — використовуй наявний префікс модуля (`WORKSHOP_*`, `GUILD_EVENTS_*`, `GROUP_FINDER_*`) і, якщо подія змінює персистентний стан, стріляй її **після** запису в БД.

---

## 13. Тести й CI

### Локальний запуск

```bash
cd ~/Projects/old-kraken-alpha
for test in tests/test_*.py; do python "$test" || exit 1; done
```

- **29 файлів** `tests/test_*.py`, ~3192 рядки.
- Рантайм: `lupa==2.8`, `from lupa.lua51 import LuaRuntime` — **Lua 5.1**.
- **`.venv` не потрібен**: системний Python 3.14.5 має `lupa 2.8`; `lua`/`lua5.1`/`luac` у системі **немає**.
- **Немає pytest/unittest/conftest/Makefile/requirements** — це прості скрипти з Lua-`assert` усередині `lua.execute('''…''')`, успіх = `print('PASS: …')`.
- Тести **не парсять TOC** — вантажать `*.lua` вручну в потрібному порядку. Тому **нових файлів у TOC недостатньо** — якщо файл має тестуватися, додай його в порядок завантаження у відповідному тесті.
- Перевірка синтаксису без `luac`: `lua.execute('assert(loadstring(...))', src)` — `tests/test_roster_invite.py` проганяє так **усі** `*.lua`.
- Двохклієнтна симуляція: `tests/test_two_clients.py` (два `LuaRuntime`, `flush(sender, recipients)`, `reload(client)` зі збереженням `OldKraken.DB`).

### Пастки

- **`tests/test_events_relay_authority.py` — інертний.** 5 функцій `test_*` без top-level викликів і без `__main__` → під `python tests/test_events_relay_authority.py` не перевіряє **нічого** (rc=0, без виводу). При цьому `TESTING.md` у розділі «Guild Events: перевірка авторитетності relay» посилається на нього як на покриття relay authority. **Relay-інваріанти фактично не захищені CI.** Якщо чіпаєш релей — або додай `__main__`-раннер (як у трьох workshop-тестах), або перевіряй уручну.
- **4 файли мовчать на успіху:** `test_events_relay_authority.py`, `test_events_ui.py`, `test_ui_hub.py`, `test_ui_style.py`. З них інертний лише перший.
- **`__main__`-раннер мають лише 3 файли:** `test_workshop_orders.py`, `test_workshop_navigation.py`, `test_workshop_sync.py`. Решта покладаються на виконання при імпорті.
- Тести **не доводять** реальну сумісність з білдом 70938, реальну доставку GUILD-повідомлень, читання книги професій, захищені дії. Це прямо перелічено в розділі `TESTING.md` «Межі автоматизованих тестів» і в примітках до окремих сценаріїв.
- Щоб не смітити: запускай з `PYTHONDONTWRITEBYTECODE=1` / `python -B` (є `.gitignore` для `__pycache__`, але краще не створювати).

### CI

| Воркфлоу | Тригер | Що робить |
|---|---|---|
| `validate-pr.yml` | PR + push у `main`/`alpha` (**`alpha` — незакомічена зміна**) | Python 3.12, `lupa==2.8`, перевірка існування файлів з TOC через `awk`, потім цикл по `tests/test_*.py` |
| `package-alpha.yml` | push у `alpha` + manual | Збирає ZIP з TOC-файлів + `Media/OldKrakenKraken.tga`, `OldKrakenEmblem.tga`, `RoleSlot.tga`, `StatusOnline.tga`, `StatusOffline.tga` |
| `package-release.yml` | релізний | Те саме для релізу |

**Усі воркфлоу парсять TOC через `awk`** — файл, доданий у TOC і відсутній на диску, валить CI і пакування.

---

## 14. Розбіжності документації з кодом

Ці місця **вже неправильні** — не орієнтуйся на них, і якщо редагуєш відповідний розділ, виправ:

| Де | Що каже | Факт |
|---|---|---|
| `README.md`, розділ про схему БД | схема БД `2` | `SCHEMA_VERSION = 3` |
| `README.md`, ZIP-listing | без `RoleSlot.tga`/`StatusOnline.tga`/`StatusOffline.tga` | `package-*.yml` їх копіюють |
| `README.md`, розділ про ростер | кнопка «Оновити» в ростері | такої кнопки немає |
| `README.md`, розділ про ростер | регістрозалежне сортування за локацією | регістронезалежне |
| `README.md`, розділ про транспорт | «обмеження 50 … не більше п'яти спроб» | `MAX_QUEUE = 4096`, ліміту спроб **немає** |
| `TESTING.md`, «Автоматизоване покриття» | «19 тестових файлів» | **29** |
| `TESTING.md`, розділ про relay | посилається на relay-authority тест | тест **інертний** |
| `Communication.lua`, коментар у `Encode` | «GF1 payloads…» | тег кадру `GF2` |
| `README.md` / `TESTING.md`, згадка останнього CI | останній CI-ран | `f11f895` — застаріло |

Розділ `README.md` про транспорт навпаки **правильний**: `SendProtocol` повертає `true` = «поставлено в чергу», **не** «доставлено». Тримай це формулювання.

`docs/EVENTS_EXTERNAL_STORAGE.md` — **пропозиція**, нічого не реалізовано (ні сервера, ні супутника, ні вебкалендаря). Не починай її реалізовувати без явного запиту; там є обов'язкові «перевірити на реальному клієнті» гейти.

---

## 15. Процес роботи

### Перед зміною

1. `git status -sb` + `git log --oneline -1` — переконайся, що не наступиш на чужу роботу.
2. Знайди **всі** місця використання API, який чіпаєш: `grep -rn "<Name>" --include="*.lua" .` — модулі щільно пов'язані, і кодек/`RegisterHandler`/`VALID_TYPES`/identity-порівняння зачіпають багато файлів одночасно.
3. Якщо додаєш поле в payload — перевір `maxFields` у відповідному `_unpackFields` і ліміт 2560 B.
4. Якщо додаєш секцію БД — онови `DEFAULTS`, міграцію, `EnsureTable`, `tests/test_database.py`, `TESTING.md`.
5. Якщо додаєш файл — допиши в `OldKraken.toc` у **правильне** місце (див. §3) і, за потреби, у порядок завантаження тестів.

### Після зміни

```bash
for test in tests/test_*.py; do python "$test" || exit 1; done
```

Усі 29 мусять пройти. Потім — ручні сценарії з `TESTING.md` (у грі), бо автоматика не покриває реальний клієнт.

### Чого не робити

- Не комітити й не пушити без явного прохання.
- Не чіпати незакомічені зміни інших агентів (§2).
- Не вводити XML, зовнішні бібліотеки, нові глобали, `Ambiguate`, `UnitGroupRolesAssigned`.
- Не переписувати relay-authority правила «для спрощення» — вони навмисні (релейник не доведе особу).
- Не трактувати `WOACT`/`WOPAYR`-заглушки і `WorkshopDeliveries`-пасивність як баги.
- Не «виправляти» `README.md`/`TESTING.md` масово — виправляй точково, коли редагуєш відповідний розділ.
