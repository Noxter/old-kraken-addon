from pathlib import Path

from lupa.lua51 import LuaRuntime


source = (Path(__file__).resolve().parents[1] / 'GroupFinderChat.lua').read_text(encoding='utf-8')


def client(registration):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
    registered=0
    shown=0
    OldKraken={GroupFinder={Show=function() shown=shown+1 end}}
    function SetItemRef() end
    function hooksecurefunc(name, fn)
        assert(name=='SetItemRef'); linkHook=fn
    end
    function addFilter(event, callback)
        assert(event=='CHAT_MSG_GUILD'); registered=registered+1; filter=callback
    end
    function CreateFrame()
        return {RegisterEvent=function(_,event) assert(event=='PLAYER_LOGIN') end,
            SetScript=function(_,_,fn) login=fn end}
    end
    ''' + registration)
    lua.execute(source)
    return lua


for registration in (
    'ChatFrameUtil={AddMessageEventFilter=addFilter}',
    'ChatFrame_AddMessageEventFilter=addFilter',
    "ChatFrameUtil={AddMessageEventFilter=function() error('unavailable') end}; ChatFrame_AddMessageEventFilter=addFilter",
):
    lua = client(registration)
    lua.execute('''
    assert(registered==1); login(); assert(registered==1)
    local examples={
        'LFG Фортеця Темного Ікла (SFK) · lvl 22–30 · потрібні: Танк, Лікар — Old Kraken',
        '{rt8} LFG Печери · lvl 20–30 »»» Old Kraken · Групи {rt8}',
        '|TInterface/TargetingFrame/UI-RaidTargetingIcon_8:0|t LFG Raid »»» Old Kraken · Groups',
        '[Old Kraken] Збір групи: Назва (1/5) — запис у вкладці «Групи» (/okr).',
        '[Old Kraken] Forming a group: Name (1/5) — sign up under Groups (/okr).',
    }
    for _,msg in ipairs(examples) do
        local hide,changed,sender,language,channel,flag=filter(nil,'CHAT_MSG_GUILD',msg,'Alice','Ukrainian',nil,7)
        assert(hide==false and type(changed)=='string' and changed:find('|Holdkraken:groups|h',1,true) and changed:find('|cffe0b052',1,true))
        assert(sender=='Alice' and language=='Ukrainian' and channel==nil and flag==7)
    end
    local _, sfkFormatted = filter(nil,'CHAT_MSG_GUILD',examples[1],'Alice','Ukrainian',nil,7)
    assert(sfkFormatted == '|cffe0b052LFG Фортеця Темного Ікла (SFK)|r|cff9aa4b2 · |r|cff9aa4b2lvl 22–30|r|cff9aa4b2 · |r|cfff3ebd3потрібні: Танк, Лікар|r |cff2ec4b6|Holdkraken:groups|h[Відкрити групи]|h|r')
    linkHook('oldkraken:groups'); assert(shown==1)
    linkHook('item:12345'); assert(shown==1)
    local unrelated={
        'Привіт, гільдіє!',
        'LFG Печери',
        'Новини Old Kraken · Групи',
        '[Old Kraken] Нова подія',
        '[Old Kraken] New event',
    }
    for _,msg in ipairs(unrelated) do
        assert(select('#',filter(nil,'CHAT_MSG_GUILD',msg,'Alice'))==1)
        assert(filter(nil,'CHAT_MSG_GUILD',msg,'Alice')==false)
    end
    assert(select('#',filter(nil,'CHAT_MSG_OFFICER',examples[1],'Alice'))==1)
    function issecretvalue(value) return value==examples[1] end
    assert(select('#',filter(nil,'CHAT_MSG_GUILD',examples[1],'Alice'))==1)
    issecretvalue=nil; function canaccessvalue() return false end
    assert(select('#',filter(nil,'CHAT_MSG_GUILD',examples[2],'Alice'))==1)
    ''')

lua = client('')
lua.execute('''
assert(registered==0)
ChatFrameUtil={AddMessageEventFilter=addFilter}
login(); login(); assert(registered==1)
''')

print('Guild group announcement chat highlighting checks passed')
