"""Creation uses reusable illustrated activity cards rather than a dropdown."""
from pathlib import Path
import runpy

ROOT=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(ROOT/'tests/test_ui_smoke.py'))['lua']
lua.execute('''
function UnitLevel() return 17 end
local ui=OldKrakenGroupFinderFrame
for _,entry in ipairs(ui.tabs) do if entry.key=='create' then entry.button.scripts.OnClick() end end
selectDropdown(ui.categoryButton,'dungeon')
local picker=ui.activityPicker
if picker then picker:Hide() end
ui.dungeonButton.scripts.OnClick()
picker=assert(ui.activityPicker)
assert(picker:IsShown() and rawget(ui.dungeonButton,'dropdownInit')==nil)
local cards=0
local rfc,wc,scholo
for _,card in ipairs(picker.cards) do
    if card:IsShown() and card.entry then
        cards=cards+1; assert(card.entry.value~='')
        assert(card.art.texture and card.title.text==card.entry.label)
        if card.entry.value=='rfc' then rfc=card end
        if card.entry.value=='wc' then wc=card end
        if card.entry.value=='scholo' then scholo=card end
    end
end
assert(cards==#OldKraken.ActivityCatalog.dungeon-1)
assert(rfc.fitsLevel and wc.fitsLevel and not scholo.fitsLevel)
assert(rfc.levels.text:find('під ваш рівень',1,true))
local allocated=#createdFrames
ui.titleBox:SetText('My custom title')
wc.scripts.OnClick(wc)
assert(not picker:IsShown() and ui.titleBox:GetText()=='My custom title')
assert(ui.minBox:GetText()=='17' and ui.maxLevelBox:GetText()=='24')
assert(ui.dungeonButton.text=='Печери Стогонів (WC)')
for i=1,10 do ui.dungeonButton.scripts.OnClick(); ui.dungeonButton.scripts.OnClick() end
assert(#createdFrames==allocated,'reopening the picker must reuse cards')
selectDropdown(ui.categoryButton,'raid')
ui.dungeonButton.scripts.OnClick()
local raids=0
for _,card in ipairs(picker.cards) do if card:IsShown() and card.entry then raids=raids+1 end end
assert(raids==#OldKraken.ActivityCatalog.raid-1)
assert(picker.heading.text=='Оберіть рейд')
picker.cards[1].scripts.OnClick(picker.cards[1])
assert(ui.minBox:GetText()=='60' and ui.maxLevelBox:GetText()=='60')
ui.dungeonButton.scripts.OnClick()
for _,entry in ipairs(ui.tabs) do if entry.key=='all' then entry.button.scripts.OnClick() end end
assert(not picker:IsShown(),'picker must close when leaving creation')
''')
print('PASS: illustrated dungeon/raid cards, level highlighting, selected activity, custom title, recommended levels, widget reuse and tab lifecycle')
