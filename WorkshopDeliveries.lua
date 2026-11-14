-- Observe confirmed trade and mail transfers; never initiate a trade or mail action.
local orders=OldKraken.WorkshopOrders
local trade,attachments,outgoing,pendingMail=nil,{},nil,{}
local function plain(value)
    if type(issecretvalue)=='function' and issecretvalue(value) then return nil end
    return value
end
local function number(value,max)
    value=plain(value)
    if type(value)~='number' or value~=value or value%1~=0 or value<0 or value>max then return nil end
    return value
end
local function text(value)
    value=plain(value); if type(value)=='string' and value~='' and #value<=128 then return value end
end
local function itemID(link)
    link=plain(link); return type(link)=='string' and tonumber(link:match('item:(%d+)')) or nil
end
local function add(items,id,count)
    id,count=number(id,100000000),number(count,1000000)
    if id and id>0 and count and count>0 then items[id]=(items[id] or 0)+count end
end
local function safeCall(fn,...)
    if type(fn)~='function' then return false end
    return pcall(fn,...)
end
local function partner()
    local ok,a,b=safeCall(UnitName,'NPC'); a,b=text(a),text(b)
    if not ok or not a then return nil end
    return b and (a..' '..b) or a
end
local function tradeItems(linkFn,infoFn)
    if type(linkFn)~='function' or type(infoFn)~='function' then return nil end
    local result={}
    for i=1,6 do
        local ok,link=safeCall(linkFn,i); local got,_,_,count=safeCall(infoFn,i)
        if not ok or not got then return nil end
        local id=itemID(link); count=number(count,1000000)
        if count and count>0 and not id then return nil end
        if id and not count then return nil end
        add(result,id,count)
    end
    return result
end
local function tradeMoney(fn)
    if type(fn)~='function' then return 0 end
    local ok,value=safeCall(fn); if not ok then return nil end
    return number(value,1000000000)
end
local function readTrade()
    if not trade or trade.closed then return end
    local given=tradeItems(GetTradePlayerItemLink,GetTradePlayerItemInfo)
    local received=tradeItems(GetTradeTargetItemLink,GetTradeTargetItemInfo)
    local paid=tradeMoney(GetPlayerTradeMoney); local got=tradeMoney(GetTargetTradeMoney)
    trade.valid=given~=nil and received~=nil and paid~=nil and got~=nil
    if trade.valid then trade.given,trade.received,trade.paid,trade.got=given,received,paid,got end
end
local function mailAttachments()
    if type(GetSendMailItem)~='function' then return nil end
    local result={}; local maximum=number(ATTACHMENTS_MAX_SEND,100) or 12
    for i=1,maximum do
        local ok,_,id,_,count=safeCall(GetSendMailItem,i); if not ok then return nil end
        id,count=number(id,100000000),number(count,1000000)
        if not id and type(GetSendMailItemLink)=='function' then local got,link=safeCall(GetSendMailItemLink,i); if got then id=itemID(link) end end
        if count and count>0 and not id then return nil end
        if id and not count then return nil end
        add(result,id,count)
    end
    return result
end
local function snapshotMail(index)
    if type(GetInboxHeaderInfo)~='function' or type(GetInboxItem)~='function' then return nil end
    local ok,_,_,sender,subject,money,cod,_,_,_,returned=safeCall(GetInboxHeaderInfo,index)
    sender,subject=text(sender),plain(subject)
    if not ok or not sender or type(subject)~='string' or plain(returned)==true or (number(cod,1000000000) or 0)>0 then return nil end
    local items,slots={},{}; local maximum=number(ATTACHMENTS_MAX_RECEIVE,100) or 16
    for i=1,maximum do
        local got,_,id,_,count=safeCall(GetInboxItem,index,i); if not got then return nil end
        id,count=number(id,100000000),number(count,1000000)
        if not id and type(GetInboxItemLink)=='function' then local has,link=safeCall(GetInboxItemLink,index,i); if has then id=itemID(link) end end
        if count and count>0 and not id then return nil end
        if id and not count then return nil end
        if id and count and count>0 then add(items,id,count); slots[i]={id=id,count=count} end
    end
    return {sender=sender,subject=subject,money=number(money,1000000000) or 0,items=items,slots=slots}
end
local function rememberTake(index,slot,all,wantMoney)
    index=number(index,10000); if not index or index<1 then return end
    local current=pendingMail[index]
    if not current then
        local before=snapshotMail(index); if not before then return end
        local ok,total=safeCall(GetInboxNumItems)
        current={before=before,requested={},money=false,mailboxCount=ok and number(total,10000) or nil,started=GetTime()}; pendingMail[index]=current
    end
    if all then for _,item in pairs(current.before.slots) do current.requested[item.id]=current.before.items[item.id] end
    else
        slot=number(slot,100); local item=slot and current.before.slots[slot]
        if item then current.requested[item.id]=current.before.items[item.id] end
    end
    if wantMoney then current.money=true end
end
local function confirmMail()
    local pending=pendingMail; pendingMail={}
    for index,entry in pairs(pending) do
        local after=snapshotMail(index); local before=entry.before
        if (not after or after.sender~=before.sender or after.subject~=before.subject) and entry.mailboxCount then
            local ok,total=safeCall(GetInboxNumItems); total=ok and number(total,10000) or nil
            local match,matches=nil,0
            if total then for i=1,total do
                local candidate=snapshotMail(i)
                if candidate and candidate.sender==before.sender and candidate.subject==before.subject then match=candidate; matches=matches+1 end
            end end
            if matches==1 then after=match
            elseif matches==0 and total and total==entry.mailboxCount-1 then
                local allRequested=true
                for id,n in pairs(before.items) do if (entry.requested[id] or 0)<n then allRequested=false; break end end
                if allRequested and (before.money==0 or entry.money) then after={sender=before.sender,subject=before.subject,items={},money=0} else after=nil end
            else after=nil end
        end
        if after and after.sender==before.sender and after.subject==before.subject then
            local received={}
            for id,wanted in pairs(entry.requested) do
                local amount=math.min(wanted,math.max(0,(before.items[id] or 0)-(after.items[id] or 0)))
                if amount>0 then received[id]=amount end
            end
            local money=entry.money and math.max(0,before.money-after.money) or 0
            if next(received) or money>0 then orders:RecordExchange(before.sender,nil,received,0,money)
            elseif GetTime()-entry.started<5 then pendingMail[index]=entry end
        elseif GetTime()-entry.started<5 then
            pendingMail[index]=entry
        end
    end
end
local function hook(target,name,callback)
    if type(hooksecurefunc)~='function' or type(target)~='table' or type(target[name])~='function' then return end
    pcall(hooksecurefunc,target,name,function(...) pcall(callback,...) end)
end
local events=CreateFrame('Frame')
for _,event in ipairs({'TRADE_SHOW','TRADE_CLOSED','TRADE_PLAYER_ITEM_CHANGED','TRADE_TARGET_ITEM_CHANGED','TRADE_MONEY_CHANGED','TRADE_ACCEPT_UPDATE','UI_INFO_MESSAGE','UI_ERROR_MESSAGE','MAIL_SEND_INFO_UPDATE','MAIL_SEND_SUCCESS','MAIL_FAILED','MAIL_INBOX_UPDATE','MAIL_CLOSED','PLAYER_LEAVING_WORLD'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event,a,b)
    if event=='TRADE_SHOW' then trade={name=partner()}; readTrade()
    elseif event=='TRADE_CLOSED' then if trade then trade.closed=true; trade.closedAt=GetTime() end
    elseif event=='TRADE_PLAYER_ITEM_CHANGED' or event=='TRADE_TARGET_ITEM_CHANGED' or event=='TRADE_MONEY_CHANGED' or event=='TRADE_ACCEPT_UPDATE' then readTrade()
    elseif event=='UI_INFO_MESSAGE' then
        local message=text(b) or text(a)
        if trade and trade.valid and trade.name and message and type(ERR_TRADE_COMPLETE)=='string' and message==ERR_TRADE_COMPLETE and (not trade.closed or GetTime()-trade.closedAt<=5) then
            local done=trade; trade=nil; orders:RecordExchange(done.name,done.given,done.received,done.paid,done.got)
        end
    elseif event=='MAIL_SEND_INFO_UPDATE' then attachments=mailAttachments() or {}
    elseif event=='MAIL_SEND_SUCCESS' then
        local sent=outgoing; outgoing=nil; attachments={}
        if sent then orders:RecordExchange(sent.name,sent.items,nil,sent.money,0) end
    elseif event=='MAIL_FAILED' then outgoing=nil; attachments={}
    elseif event=='MAIL_INBOX_UPDATE' then confirmMail()
    elseif event=='UI_ERROR_MESSAGE' then
        local message=text(b) or text(a)
        if message and (message==ERR_INV_FULL or message==ERR_ITEM_MAX_COUNT or message==ERR_MAIL_DATABASE_ERROR) then pendingMail={} end
    elseif event=='MAIL_CLOSED' or event=='PLAYER_LEAVING_WORLD' then pendingMail={}; outgoing=nil; attachments={}; trade=nil end
end)
local function captureOutgoing(recipient)
    recipient=text(recipient); if not recipient then outgoing=nil; return end
    local items=mailAttachments(); if not items or not next(items) then items=attachments end
    local ok,money=safeCall(GetSendMailMoney); outgoing={name=recipient,items=items or {},money=ok and (number(money,1000000000) or 0) or 0}
end
hook(_G,'SendMail',captureOutgoing); if type(C_Mail)=='table' then hook(C_Mail,'SendMail',captureOutgoing) end
hook(_G,'TakeInboxItem',function(index,slot) rememberTake(index,slot,false,false) end)
hook(_G,'TakeInboxMoney',function(index) rememberTake(index,nil,false,true) end)
hook(_G,'AutoLootMailItem',function(index) rememberTake(index,nil,true,true) end)
