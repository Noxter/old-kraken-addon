from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LOCALE = (ROOT / 'Locale.lua').read_text(encoding='utf-8')
CATALOG = (ROOT / 'ActivityCatalog.lua').read_text(encoding='utf-8')


def run_catalog(lang):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._lang = lang
    lua.execute('''
        OldKraken = { name = 'OldKraken' }
    ''')
    lua.execute(LOCALE)
    lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
    lua.execute(CATALOG)
    lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
    return lua


for lang, expected_lbrs, expected_ubrs in (
    ('ukUA', 'Нижній пік Чорної гори (LBRS)', 'Верхній пік Чорної гори (UBRS)'),
    ('enUS', 'Lower Blackrock Spire (LBRS)', 'Upper Blackrock Spire (UBRS)'),
):
    lua = run_catalog(lang)
    lua.globals()._exp_lbrs = expected_lbrs
    lua.globals()._exp_ubrs = expected_ubrs
    lua.execute('''
        local cat = OldKraken.ActivityCatalog
        assert(cat.IsValidActivity('dungeon', 'lbrs'))
        assert(cat.IsValidActivity('dungeon', 'ubrs'))
        local found = {}
        for _, entry in ipairs(cat.dungeon) do
            if entry.value == 'lbrs' or entry.value == 'ubrs' then
                found[entry.value] = entry
            end
        end
        assert(found.lbrs and found.lbrs.label == _exp_lbrs and found.lbrs.min == 55 and found.lbrs.max == 60)
        assert(found.ubrs and found.ubrs.label == _exp_ubrs and found.ubrs.min == 58 and found.ubrs.max == 60)
        assert(cat.IsCanonicalTitle('lbrs', _exp_lbrs))
        assert(cat.IsCanonicalTitle('ubrs', _exp_ubrs))
        assert(cat.IsCanonicalTitle('lbrs', 'Пік Чорної гори (BRS)'))
        assert(cat.IsCanonicalTitle('lbrs', 'Blackrock Spire (BRS)'))

        local texL, texU = {}, {}
        function texL:SetTexture(v) self.tex = v end
        function texL:SetTexCoord() end
        function texU:SetTexture(v) self.tex = v end
        function texU:SetTexCoord() end
        cat.SetArtwork(texL, 'lbrs')
        cat.SetArtwork(texU, 'ubrs')
        assert(texL.tex == 131825 and texU.tex == 131825)
    ''')

# Verify GroupFinder and GuildEvents accept ubrs and lbrs
lua_full = LuaRuntime(unpack_returned_tuples=True)
lua_full.execute('''
    now = 1700000000
    OldKraken = { name = 'OldKraken', DB = { settings = { language = 'ukUA' } } }
    function OldKraken:On() end
    function OldKraken:Fire() end
    function GetServerTime() return now end
    function GetTime() return 100 end
    function UnitClass() return 'Warrior', 'WARRIOR' end
    function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
''')
lua_full.execute(LOCALE)
lua_full.execute('OldKraken.InitializeLocale(OldKraken.DB)')
lua_full.execute(CATALOG)
lua_full.execute((ROOT / 'GroupFinder.lua').read_text(encoding='utf-8'))
lua_full.execute('''
    local gf = OldKraken.GroupFinder
    gf.active, gf.identity, gf.groups, gf.sequence = true, 'Leader', {}, 0
    gf.requestVersions, gf.reopenFloors, gf.lastActivity = {}, {}, {}
    gf.send = function() return true end
    local ok, id = gf:Create('Верхній пік Чорної гори (UBRS)', 'dungeon', '', 5, 58, 60, 'tank', 'ubrs')
    assert(ok == true and type(id) == 'string', tostring(id))
    local g = gf.groups['Leader\\001' .. id]
    assert(type(g) == 'table' and g.dungeon == 'ubrs')
''')

print('Blackrock Spire wings checks passed')
