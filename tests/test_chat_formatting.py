from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LOCALE = (ROOT / 'Locale.lua').read_text(encoding='utf-8')
CORE = (ROOT / 'Core.lua').read_text(encoding='utf-8')


def run_core_test(lang='ukUA'):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._lang = lang
    lua.execute('''
        printed = {}
        function print(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            printed[#printed + 1] = table.concat(parts, ' ')
        end
        function CreateFrame()
            return { RegisterEvent = function() end, SetScript = function() end }
        end
        OldKraken = {}
    ''')
    lua.execute(LOCALE)
    lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
    lua.execute(CORE)
    return lua


# 1. Core Print / PrintError normalization (dot and colon syntax)
lua = run_core_test('ukUA')
lua.execute('''
    local T = OldKraken.Translate
    OldKraken:Print('звичайне повідомлення')
    OldKraken.Print('Old Kraken: без кольору')
    OldKraken:PrintError('Old Kraken: помилка без кольору')
    OldKraken:PrintError('|cff2ec4b6Old Kraken|r: старий бірюзовий префікс')
    OldKraken:Print('|cffff5555Old Kraken|r: старий червоний префікс')
    assert(printed[1] == '|cff2ec4b6Old Kraken|r: звичайне повідомлення')
    assert(printed[2] == '|cff2ec4b6Old Kraken|r: без кольору')
    assert(printed[3] == '|cffff5555Old Kraken|r: помилка без кольору')
    assert(printed[4] == '|cffff5555Old Kraken|r: старий бірюзовий префікс')
    assert(printed[5] == '|cff2ec4b6Old Kraken|r: старий червоний префікс')
    assert(T('[Групи]') == '[Групи]' and T('[Івенти]') == '[Івенти]' and T('[Майстерня]') == '[Майстерня]')
''')

# 2. English localization preserves translation + normalizes prefix
lua_en = run_core_test('enUS')
lua_en.execute('''
    local T = OldKraken.Translate
    OldKraken:PrintError(T('Old Kraken: пошук груп не ініціалізовано.'))
    OldKraken:Print(T('Old Kraken: запит професій поставлено в чергу.'))
    assert(printed[1] == '|cffff5555Old Kraken|r: Group Finder is not initialized.')
    assert(printed[2] == '|cff2ec4b6Old Kraken|r: Profession request queued.', printed[2])
    assert(T('[Групи]') == '[Groups]' and T('[Івенти]') == '[Events]' and T('[Майстерня]') == '[Workshop]')
''')

# 3. Runtime logAlert formatting for group, event, and workshop alerts
ui_lua = LuaRuntime(unpack_returned_tuples=True)
ui_lua.execute('''
    printed = {}
    function print(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        printed[#printed + 1] = table.concat(parts, ' ')
    end
    function CreateFrame()
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    function InCombatLockdown() return true end
    function GetServerTime() return 1700000000 end
    function date() return '20:00' end
    StaticPopupDialogs = {}
    UIParent = {}
    OldKraken = { DB = { settings = { smartNotifications = true } } }
''')
ui_lua.execute(LOCALE)
ui_lua.execute('OldKraken.InitializeLocale({ settings = { language = "ukUA" } })')
ui_lua.execute(CORE)
ui_lua.execute((ROOT / 'ActivityCatalog.lua').read_text(encoding='utf-8'))
ui_lua.execute((ROOT / 'GroupFinder.lua').read_text(encoding='utf-8'))
ui_lua.execute((ROOT / 'GroupFinderUI.lua').read_text(encoding='utf-8'))
ui_lua.execute('''
    OldKraken:Fire('GROUP_FINDER_APPLICATION_STATUS', { owner = 'Alice', id = 'g1', title = 'Kara' }, 'reject')
    OldKraken:Fire('GUILD_EVENTS_NEW', 'e1', { id = 'e1', owner = 'Bob', title = 'MC', when = 1700000000 })
    OldKraken:Fire('WORKSHOP_ORDER_NOTICE', 'Нове замовлення', 'Flask x5', 'o1')
    assert(printed[1]:find('|cff2ec4b6Old Kraken|r: %[Групи%] ', 1) == 1, printed[1])
    assert(printed[2]:find('|cff2ec4b6Old Kraken|r: %[Івенти%] ', 1) == 1, printed[2])
    assert(printed[3]:find('|cff2ec4b6Old Kraken|r: %[Майстерня%] ', 1) == 1, printed[3])
    for i = 1, 3 do
        assert(not printed[i]:find('/okr ', 1, true), printed[i])
    end
''')

print('Chat formatting checks passed')
