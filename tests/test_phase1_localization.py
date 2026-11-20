from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
ui = (root / 'GroupFinderUI.lua').read_text(encoding='utf-8')
helper = 'local function displayGroupTitle(group)' + ui.split('local function displayGroupTitle(group)', 1)[1].split('local activityOptions', 1)[0]
for language, source_title, displayed in [
    ('enUS', 'Вогненна прірва (RFC)', 'Ragefire Chasm (RFC)'),
    ('ukUA', 'Ragefire Chasm (RFC)', 'Вогненна прірва (RFC)'),
]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('OldKraken={}; function GetTime() return 1 end; function GetServerTime() return 1700000000 end')
    for name in ('Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua'):
        lua.execute((root / name).read_text(encoding='utf-8'))
    lua.globals().language, lua.globals().sourceTitle, lua.globals().expected = language, source_title, displayed
    lua.execute(r'''
        OldKraken.InitializeLocale({settings={language=language}})
        local catalog=OldKraken.ActivityCatalog
        local dungeonLabels={}
        for _,list in ipairs({catalog.dungeon,catalog.raid}) do
            for _,entry in ipairs(list) do dungeonLabels[entry.value]=entry.label end
        end
    ''' + helper + r'''
        local finder=OldKraken.GroupFinder
        assert(displayGroupTitle(nil)=='' and displayGroupTitle(false)=='' and displayGroupTitle(42)=='')
        assert(displayGroupTitle({title=42})=='')
        finder:Initialize('Owner Realm',function() return true end)
        local ok,id=finder:Create(sourceTitle,'dungeon','',5,1,60,'tank','rfc'); assert(ok)
        local group=finder.groups['Owner Realm\001'..id]
        local before=finder:EncodeGroup(group)
        assert(displayGroupTitle(group)==expected)
        assert(group.title==sourceTitle and finder:EncodeGroup(group)==before)
        group.title='Custom'; assert(displayGroupTitle(group)=='Custom')
        group.title=sourceTitle; group.dungeon='unknown'; assert(displayGroupTitle(group)==sourceTitle)
        group.dungeon=''; assert(displayGroupTitle(group)==sourceTitle)
    ''')
print('Phase 1 localization checks passed')
