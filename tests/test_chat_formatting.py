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

# 3. GroupFinderUI logAlert uses readable module labels instead of /okr commands
ui_src = (ROOT / 'GroupFinderUI.lua').read_text(encoding='utf-8')
assert '. /okr events' not in ui_src and '. /okr orders' not in ui_src and '. /okr group' not in ui_src
assert "T('[Івенти]')" in ui_src and "T('[Майстерня]')" in ui_src and "T('[Групи]')" in ui_src

print('Chat formatting checks passed')
