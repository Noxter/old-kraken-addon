# Дослідження Native Group Finder API (WoW Forever 1.60.1)

Цей документ містить результати технічного ресерчу наявного API пошуку груп (`C_LFGList`) у клієнті WoW Forever 1.60.1 (build 70938, Interface 16001).

---

## 1. Стан API у перевіреному клієнті

Попередні діагностичні перевірки у грі підтвердили:
- `C_LFGList` та `C_LFGInfo` — існують як глобальні таблиці.
- Доступні функції: `C_LFGList.GetAvailableActivities`, `GetSearchResults`, `GetSearchResultInfo`, `Search`, `CreateListing`, `UpdateListing`.
- `C_LFGList.RequestToJoin` — повертає `nil`.
- `LFGListFrame` — глобальний фрейм відсутній (`nil`), що означає відсутність стандартного Blizzard UI для LFG у цьому білді.

Ще не підтверджено безпосередньо в грі: `GetAvailableCategories`, `GetActivityInfoTable`, `GetSearchResultPlayerInfo`, `ApplyToGroup`, `IsPremadeGroupFinderEnabled`.

---

## 2. Обмеження та безпека викликів

- Документація API flavor Camelot позначає `Search` та `CreateListing` як restricted у певних контекстах.
- Метод `ApplyToGroup` у довідниках позначений як припущений і відсутній в офіційних специфікаціях.
- Тому код Old Kraken **не викликає** методи мутації нативного LFG (`Search`, `CreateListing`, `ApplyToGroup`), щоб уникнути помилок UI або блокувань клієнта.
- Команда `/okr group api` виконує виключно безпечну діагностику **в режимі читання (read-only)**.

---

## 3. Джерела документації

- [C_LFGList для Camelot](https://wowlua.dev/api/C_LFGList)
- [C_LFGList.Search](https://wowlua.dev/api/C_LFGList/Search)
- [C_LFGList.GetSearchResults](https://wowlua.dev/api/C_LFGList/GetSearchResults)
- [C_LFGList.GetSearchResultInfo](https://wowlua.dev/api/C_LFGList/GetSearchResultInfo)
- [C_LFGList.CreateListing](https://wowlua.dev/api/C_LFGList/CreateListing)
