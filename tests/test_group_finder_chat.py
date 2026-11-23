from pathlib import Path

from lupa.lua51 import LuaRuntime


source = (Path(__file__).resolve().parents[1] / 'GroupFinderChat.lua').read_text(encoding='utf-8')


def client(registration):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
    registered=0
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
        '{rt8} LFG Печери · lvl 20–30 »»» Old Kraken · Групи {rt8}',
        '|TInterface/TargetingFrame/UI-RaidTargetingIcon_8:0|t LFG Raid »»» Old Kraken · Groups',
        '[Old Kraken] Збір групи: Назва (1/5) — запис у вкладці «Групи» (/okr).',
        '[Old Kraken] Forming a group: Name (1/5) — sign up under Groups (/okr).',
    }
    for _,msg in ipairs(examples) do
        local hide,changed,sender,language,channel,flag=filter(nil,'CHAT_MSG_GUILD',msg,'Alice','Ukrainian',nil,7)
        assert(hide==false and changed=='|cffffd34d'..msg..'|r')
        assert(sender=='Alice' and language=='Ukrainian' and channel==nil and flag==7)
    end
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
