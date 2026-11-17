"""Dungeon cards are visible immediately inside the creation tab."""
from pathlib import Path
import runpy

ROOT=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(ROOT/'tests/test_ui_smoke.py'))['lua']
lua.execute('''
function UnitLevel() return 17 end
local ui=OldKrakenGroupFinderFrame
for _,entry in ipairs(ui.tabs) do if entry.key=='create' then entry.button.scripts.OnClick() end end
selectDropdown(ui.categoryButton,'dungeon')
local picker=assert(ui.activityPicker)
assert(picker:IsShown() and picker.parent==ui,'cards must be embedded and visible without a button click')
assert(rawget(ui,'dungeonButton')==nil,'obsolete popup button must be removed')
for _,name in ipairs(UISpecialFrames) do assert(name~='OldKrakenActivityPicker') end
local count=0
local wc,rfc,scholo
for _,card in ipairs(picker.cards) do
    if card:IsShown() and card.entry then
        count=count+1; assert(card.entry.value~='' and card.art.texture)
        if card.entry.value=='wc' then wc=card end
        if card.entry.value=='rfc' then rfc=card end
        if card.entry.value=='scholo' then scholo=card end
    end
end
assert(count==#OldKraken.ActivityCatalog.dungeon-1)
assert(wc.fitsLevel and rfc.fitsLevel and not scholo.fitsLevel)
assert(wc.levels.text:find('під ваш рівень',1,true))
picker.scripts.OnMouseWheel(picker,-1); assert(picker.offset==70)
wc.scripts.OnMouseWheel(wc,-1); assert(picker.offset==140)
local allocated=#createdFrames
ui.titleBox:SetText('Custom title')
wc.scripts.OnClick(wc)
assert(picker:IsShown() and wc.selected and picker.offset==140)
assert(ui.titleBox:GetText()=='Custom title')
assert(ui.minBox:GetText()=='17' and ui.maxLevelBox:GetText()=='24')
assert(ui.dungeonSelection.text=='Печери Стогонів (WC)')
picker:ScrollTo(100000); assert(picker.offset==picker.fullHeight-picker.viewportHeight)
picker:ScrollTo(-100); assert(picker.offset==0)
picker.clear.scripts.OnClick()
assert(picker:IsShown() and not wc.selected)
assert(ui.dungeonSelection.text=='Оберіть картку вище')
for i=1,10 do
    for _,entry in ipairs(ui.tabs) do if entry.key=='all' then entry.button.scripts.OnClick() end end
    assert(not picker:IsShown())
    for _,entry in ipairs(ui.tabs) do if entry.key=='create' then entry.button.scripts.OnClick() end end
    assert(picker:IsShown())
end
assert(#createdFrames==allocated,'reopening creation must reuse cards')
selectDropdown(ui.categoryButton,'raid')
local raids=0
for _,card in ipairs(picker.cards) do if card:IsShown() and card.entry then raids=raids+1 end end
assert(raids==#OldKraken.ActivityCatalog.raid-1 and picker.offset==0)
assert(picker.heading.text=='Оберіть рейд')
picker.cards[1].scripts.OnClick(picker.cards[1])
assert(picker:IsShown() and ui.minBox:GetText()=='60' and ui.maxLevelBox:GetText()=='60')
selectDropdown(ui.categoryButton,'quest')
assert(not picker:IsShown())
selectDropdown(ui.categoryButton,'dungeon')
assert(ui.creationFooter:IsShown() and ui.creationFooter.height==46)
assert(not ui.creationOptions:IsShown() and not ui.titleBox:IsShown())
assert(ui.descriptionBox:IsShown() and not ui.descriptionBox.label:IsShown())
assert(not ui.roleButton:IsShown() and ui.createButton.text=='Зібрати групу')
assert(picker.viewportHeight==407)
ui.creationOptionsButton.scripts.OnClick()
assert(ui.creationOptions:IsShown() and ui.titleBox:IsShown() and ui.categoryButton:IsShown())
assert(picker.viewportHeight==327)
ui.titleBox:SetText('Compact custom title')
ui.creationOptionsButton.scripts.OnClick()
assert(not ui.creationOptions:IsShown() and ui.titleBox:GetText()=='Compact custom title')
assert(picker.viewportHeight==407)
ui.creationRoles[1].scripts.OnClick()
assert(ui.creationRoles[1].active:IsShown() and not ui.creationRoles[3].active:IsShown())
for _,card in ipairs(picker.cards) do if card.entry and card.entry.value=='rfc' then card.scripts.OnClick(card) end end
ui.descriptionBox:SetText('Compact comment')
ui.createButton.scripts.OnClick()
local created
for _,group in pairs(OldKraken.GroupFinder.groups) do if group.title=='Compact custom title' then created=group end end
assert(created and created.role=='tank' and created.dungeon=='rfc' and created.description=='Compact comment')
assert(not ui.creationFooter:IsShown() and not picker:IsShown())
''')
print('PASS: immediate inline cards, clipping/scroll boundaries, selection without dismissal, cleared selection, level hints, widget reuse and category/tab lifecycle')
