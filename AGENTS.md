# AGENTS.md — правила роботи з Old Kraken (гілка `alpha`)

Інструкції для AI-агентів (OpenCode, Codex, Copilot, Antigravity, Gemini CLI, Claude Code) у цьому репозиторії.
Файл **не дублює** `README.md` і `TESTING.md` — він фіксує те, що агент мусить знати, щоб не ламати аддон і не вигадувати API.

> **Цей файл описує актуальний стан коду (`0.5.8-alpha.1` у `alpha`, `0.5.7` у `main`).** Обидві гілки містять повну структуру аддона (20 файлів), схема БД v3.
>
> **Посилання тут — на імена функцій, констант і розділів, а не на номери рядків.** Гілка `alpha` рухається швидко, тож номери рядків застарівають. Шукай за символом: `grep -rn "ReceiveGroup" --include="*.lua" .`

---

> **Обсяг:** це ядро жорстких правил. Детальні описи транспорту, модулів, команд і тестів винесено в `docs/ARCHITECTURE.md`; номери секцій там **ті самі**, тому посилання на кшталт «див. §11» лишаються чинними. Відкривай релевантну секцію перед роботою з відповідним кодом. Чисельний лічильник у §1 є історичним — перевіряй `wc -l`.

## 1. Що це і для чого

Аддон WoW на Lua для україномовної гільдії: реєстр гільдії, Group Finder (пошук групи), гільдійний календар подій, «майстерня» (професії, рецепти, замовлення на крафт).

- **Цільовий клієнт:** WoW Forever `1.60.1 (70938)`, `## Interface: 16001`. Retail/Classic **не цільові** — не додавай гілки «для сумісності», якщо про це не просили.
- **Runtime:** **Lua 5.1**. Заборонено: `goto`, `continue`, побітові оператори (`&`, `|`, `<<`, `>>`, `~`), `//`, `table.pack`/`table.unpack` (тільки `unpack`), `#`-оператор на nil-таблицях, конструкції з 5.2+.
- Доступні хелпери WoW: `strsplit`, `strjoin`, `tinsert`, `tremove`, `wipe`, `format`, `pcall`, `C_Timer.After/NewTicker`, `GetTime`, `GetServerTime`, `hooksecurefunc`.
- **Без XML** — весь UI будується кодом. **Без зовнішніх бібліотек** (жодного LibStub/Ace3). **Без `TODO`/`FIXME`/`XXX`/`HACK`** — їх у репо немає ніде (ні `.lua`, ні `.py`, `.md`, `.yml`); обмеження описані прозою в коментарях і документації. Не додавай цих маркерів — пиши пояснення коментарем.
- **Мова:** українська за замовчуванням, англійська через налаштування. Для нового тексту інтерфейсу додавай англійський відповідник у `Locale.lua`. Коментарі, ідентифікатори й назви функцій — англійською.

### Розмір коду

20 Lua-файлів. Найбільші: `GroupFinderUI.lua` (2865), `WorkshopRecipes.lua` (1918), `GuildEvents.lua` (1677), `GuildRoster.lua` (1590), `WorkshopOrders.lua` (1401), `Core.lua` (1307).

---

## 2. Три робочі копії одного репо (перевіряй, де ти)

`https://github.com/Noxter/old-kraken-addon.git` має щонайменше три checkout-и на цій машині:

| Шлях | Гілка / стан | Призначення |
|---|---|---|
| `~/Projects/old-kraken-alpha/` | `alpha` (ця копія) | **актуальна розробка (`0.5.8-alpha.1`)** |
| `~/Projects/old-kraken-addon/` | `main` | **релізна гілка (`0.5.7`)** |
| `~/Projects/copilot-worktrees/old-kraken-addon/copilot-prewarm-fluffy-winner` | detached worktree | службовий |

**Перед початком роботи завжди:** `git status -sb` + `git log --oneline -1` у `old-kraken-alpha`. Не роби `git reset --hard`, `git checkout .`, `git stash` без підтвердження користувача.

---

## 3. Порядок завантаження (`OldKraken.toc`) — критично

`OldKraken.toc` вантажить файли **строго** в цьому порядку:

```
Database.lua          Locale.lua          Core.lua            UIHub.lua
Communication.lua     GuildRoster.lua     ActivityCatalog.lua
GroupFinder.lua       GroupFinderIntegration.lua   GroupFinderChat.lua
GroupFinderUI.lua     GroupFinderAPI.lua           GuildEvents.lua
Workshop.lua          WorkshopRecipes.lua          WorkshopSync.lua
WorkshopOrders.lua    WorkshopDeliveries.lua       Minimap.lua
ChatLayoutSwitcher.lua
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

**`SCHEMA_VERSION = 3`** у `Database.lua`.

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

`roster` (`status` = `all|online|offline`, `sort` = `name|level|class|rank|zone`, `ascending` bool, `class`, `search`), `minimapAngle`, `showMinimapButton`, `alertPositions`, `groupFinderNotifications`, `guildEventNotifications`, `workshopOrderAlerts`, `versionIndicator`, `versionChatNotifications`, `versionSessionNotified`.

Для визначення `realm` у всіх модулях використовується `Database:GetRealmScope()`: `Database:IsValidRealm("")` залишається `false`, але штатний порожній `GetRealmName() == ""` на WoW Forever `1.60.1` резолвиться в явний scope `"Forever"` (якщо `GetNormalizedRealmName()` і `GetCVar("realmName")` теж не дають валідного значення).

`NormalizeRosterSettings` **жорстко** валідує `status`/`sort`/`ascending`/`class`/`search`. Додаєш новий ключ у `settings.roster` — додай і нормалізацію.

---

## Мапа повного довідника

- **§6 Транспорт** (`Communication.lua`) — кадр `GF2^KIND^ID^PART^COUNT^HEX`,
  payload ≤ 2560 B (80×32), закритий `VALID_TYPES`, обробники реєструються на
  file scope під `pcall`, sender порівнюється сирим рядком (без `Ambiguate`).
- **§7 Group Finder** — авторитет власника, `RESPONSE` = reject-only,
  `MAX_GROUPS = 100`, ролі тільки з API, LFG-probe read-only.
- **§8 Guild Events** — релейні копії display-only, змінює лише власник,
  ≤ 100 живих подій.
- **§9 Майстерня** — спільний скоуп `workshop.guilds[realm\001guild]`, міграція
  ручна (`/okr workshop migrate`), `WOACT`/`WOPAYR` — свідомі no-op,
  `WorkshopDeliveries` — пасивний хук.
- **§10 Ростер / Minimap / UIHub / ActivityCatalog** — сортування за локацією
  регістронезалежне, кнопки «Оновити» немає (`/okr refresh`), сторінки
  UIHub створюються ліниво, catalog — єдине джерело назв і арту, `validActivity`
  виводиться з каталогу.
- **§11 Команди `/okr`** — диспетчеризація: `Communication` → `GroupFinderAPI`
  → локальні → фолбек (невідома команда відкриває ростер).
- **§12 Шина подій** — `OldKraken:On` / `Fire`; подію, що змінює БД, стріляй
  після запису.
- **§13 Тести й CI** — запуск
  `for test in tests/test_*.py; do python -B "$test" || exit 1; done`;
  Lupa 2.8 / Lua 5.1, без pytest, CI парсить TOC через `awk`.

## 14. Розбіжності документації з кодом

Ці місця **вже неправильні** — не орієнтуйся на них, і якщо редагуєш відповідний розділ, виправ:

| Де | Що каже | Факт |
|---|---|---|
| `README.md`, розділ про схему БД | схема БД `2` | `SCHEMA_VERSION = 3` |
| `README.md`, ZIP-listing | без `RoleSlot.tga`/`StatusOnline.tga`/`StatusOffline.tga` | `package-*.yml` їх копіюють |
| `README.md`, розділ про ростер | кнопка «Оновити» в ростері | такої кнопки немає |
| `README.md`, розділ про ростер | регістрозалежне сортування за локацією | регістронезалежне |
| `README.md`, розділ про транспорт | «обмеження 50 … не більше п'яти спроб» | `MAX_QUEUE = 4096`, `MAX_ERROR_ATTEMPTS = 5` |
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

Усі 64 мусять пройти. Потім — ручні сценарії з `TESTING.md` (у грі), бо автоматика не покриває реальний клієнт.

### Чого не робити

- Не комітити й не пушити без явного прохання.
- Не чіпати незакомічені зміни інших агентів (§2).
- Не вводити XML, зовнішні бібліотеки, нові глобали, `Ambiguate`, `UnitGroupRolesAssigned`.
- Не переписувати relay-authority правила «для спрощення» — вони навмисні (релейник не доведе особу).
- Не трактувати `WOACT`/`WOPAYR`-заглушки і `WorkshopDeliveries`-пасивність як баги.
- Не «виправляти» `README.md`/`TESTING.md` масово — виправляй точково, коли редагуєш відповідний розділ.

---

## 16. Performance Requirements (CPU / Lua 5.1)

Обов'язкові інженерні правила для всіх нових функцій, виправлень і рефакторингів:

- **Події та `OnUpdate`:** не залишай постійно активних `OnUpdate`-циклів на прихованих чи неактивних службових фреймах — приховуй саме службовий фрейм (`Hide()`) або знімай `OnUpdate` через `SetScript('OnUpdate', nil)`, коли роботи немає, і вмикай лише на час активного оновлення (не ховай UI-контейнери заради зупинки фонового циклу). `OnUpdate` або періодичний тікер допустимі лише за обґрунтованої потреби з чітким інтервалом і обмеженням роботи за тік.
- **Сканування та часті події:** уникай невиправданих повних пересканувань (`GetGuildRosterInfo`, каталоги, усі записи) у відповідь на часті події (`GROUP_ROSTER_UPDATE`, `SPELLS_CHANGED`, `GUILD_ROSTER_UPDATE`). Використовуй інкрементальне оновлення, якщо джерело даних дозволяє достовірно визначити змінений зріз (як `partyPeople`); якщо API не надає delta — об'єднуй повторні події через debounce/throttle, виконуй контрольоване сканування та роби early-exit, якщо стан не змінився.
- **Гарячі цикли й кеші:** не створюй анонімні замикання на кожну ітерацію (`pcall(function() ... end)`, `gsub` із callback) у гарячих шляхах — використовуй прямі виклики та попередньо побудовані lookup-таблиці або кеші з обмеженим розміром / TTL (і обов'язковим скиданням при зміні гільдії/скоупу).
- **Перевірка перед релізом:** будь-які зміни, чутливі до CPU, перевіряй у реальному клієнті WoW Forever через `/okr perf on` → активна гра → `/okr perf report` (порівнюючи `C_AddOnProfiler` та розбивку по мітках).

---

## 17. Network Efficiency (Guild Addon Communication)

Обов'язкові правила для всіх змін у протоколах і синхронізації:

- **Широкомовність `GUILD`:** канал `GUILD` доставляє кожен кадр усім онлайн-учасникам гільдії. Не додавай періодичних масових ретрансляцій або повних знімків без явної потреби, придушення дублів (`pendingTransmissions`, `relayDirty` / `WRIDX` suppression), TTL та відповідного контролю заповненості черги / backpressure (наприклад, резерв `ACTION_RESERVE = 256` при `MAX_QUEUE = 4096` для дій або локальний поріг на кшталт `#comm.queue <= 8` для фонових тікерів).
- **Раннє відсіювання та фільтрація:** перевіряй довжину, формат, валідність і `completed[key]` до `Decode()` і дорогого розбору payload; для адресованих повідомлень використовуй `Communication.part1Filters`, щоб відкидати чужі multipart-передачі на `part == 1` до збірки.
- **Асимптотика та ліміти:** тримай `O(1)` лічильники для обмежених кешів (`assemblies`, `completed`, `backups`, `indices`) і не перевищуй транспортні межі (240 B на wire-кадр, ≤ 2560 B payload, `MAX_QUEUE = 4096`, `ACTION_RESERVE = 256`).
- **Перевірка перед релізом:** зміни в мережевій логіці чи синхронізації перевіряй у грі через `/okr comm traffic reset` → сесія в гільдії → `/okr comm traffic` (оцінюючи окремо `txQ`/`rxH`, фрагменти, байти, `retries`, `rxDedup`, `filt`, `tail` та `drops`).

