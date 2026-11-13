from pathlib import Path
from lupa.lua51 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'Database.lua').read_text(encoding='utf-8')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('OldKraken = {version="0.3.3"}; OldKrakenDB = {schemaVersion=1, roster={keep="roster"}, events={keep="event"}, settings={roster={search="тест"}}}')
lua.execute(source)
lua.execute('''
local db = OldKraken.Database.Initialize()
assert(db.schemaVersion == 2 and type(db.groupFinder) == 'table')
assert(db.roster.keep == 'roster' and db.events.keep == 'event')
assert(db.settings.roster.search == 'тест')
OldKrakenDB = {schemaVersion=99, other='new'}
db = OldKraken.Database.Initialize()
assert(db.schemaVersion == 99 and db.other == 'new' and db.groupFinder == nil)
''')
print('Database migration checks passed')
