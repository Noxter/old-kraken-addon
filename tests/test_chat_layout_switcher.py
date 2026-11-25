from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def make_lua():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        OldKraken = { DB = { settings = {} } }
        NUM_CHAT_WINDOWS = 10
        local ctrlDown, altDown, shiftDown = false, false, false
        function IsControlKeyDown() return ctrlDown end
        function IsAltKeyDown() return altDown end
        function IsShiftKeyDown() return shiftDown end
        function SetModifiers(c, a, s) ctrlDown, altDown, shiftDown = c, a, s end

        local function makeEditBox()
            local box = { text = '', cursor = 0, hooks = {} }
            function box:GetText() return self.text end
            function box:SetText(v) self.text = v end
            function box:SetCursorPosition(p) self.cursor = p end
            function box:HookScript(name, fn)
                self.hooks[name] = self.hooks[name] or {}
                table.insert(self.hooks[name], fn)
            end
            function box:FireKeyDown(key)
                for _, fn in ipairs(self.hooks.OnKeyDown or {}) do
                    fn(self, key)
                end
            end
            return box
        end

        ChatFrame1EditBox = makeEditBox()
        function ChatEdit_GetActiveWindow() return ChatFrame1EditBox end
        function CreateFrame()
            local f = { scripts = {} }
            function f:RegisterEvent() end
            function f:SetScript(name, fn) self.scripts[name] = fn end
            return f
        end
        """
    )
    lua.execute((ROOT / "ChatLayoutSwitcher.lua").read_text(encoding="utf-8"))
    return lua


def test_en_to_uk_and_uk_to_en():
    lua = make_lua()
    lua.execute(
        """
        local S = OldKraken.ChatLayoutSwitcher
        assert(S:Convert('ghbdsn') == 'привіт')
        assert(S:Convert('Ghbdsn?') == 'Привіт,')
        assert(S:Convert('ghbdsn/') == 'привіт.')
        assert(S:Convert("[f'\\\\]") == 'хаєґї')
        assert(S:Convert('руддщ цщкдв') == 'hello world')
        assert(S:Convert('Руддщ!') == 'Hello!')
        assert(S:Convert('.п руддщ') == '/g hello')
        assert(S:Convert('') == '')
        assert(S:Convert('ghbdsn ₴ — 🐉') == 'привіт ₴ — 🐉')
        assert(S:Convert('руддщ ₴ — 🐉') == 'hello ₴ — 🐉')
        """
    )


def test_preserves_links_icons_and_slash_commands():
    lua = make_lua()
    lua.execute(
        """
        local S = OldKraken.ChatLayoutSwitcher
        local msg = '/g ghbdsn |cffa335ee|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r {star} |TInterface\\\\Icons\\\\INV_Misc_Coin_01:16|t rjdfk'
        local converted = S:Convert(msg)
        local expected = '/g привіт |cffa335ee|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r {star} |TInterface\\\\Icons\\\\INV_Misc_Coin_01:16|t ковал'
        assert(converted == expected, 'got: ' .. tostring(converted))
        """
    )


def test_hotkey_hook_and_setting_toggle():
    lua = make_lua()
    lua.execute(
        """
        ChatFrame1EditBox:SetText('ghbdsn')
        SetModifiers(false, false, false)
        ChatFrame1EditBox:FireKeyDown('L')
        assert(ChatFrame1EditBox:GetText() == 'ghbdsn')

        SetModifiers(true, false, false)
        ChatFrame1EditBox:FireKeyDown('L')
        assert(ChatFrame1EditBox:GetText() == 'привіт')
        assert(ChatFrame1EditBox.cursor == #'привіт')

        -- Second press converts back
        ChatFrame1EditBox:SetText('руддщ')
        ChatFrame1EditBox:FireKeyDown('L')
        assert(ChatFrame1EditBox:GetText() == 'hello')

        -- Respects disabled setting
        OldKraken.DB.settings.chatLayoutSwitcher = false
        ChatFrame1EditBox:SetText('ghbdsn')
        ChatFrame1EditBox:FireKeyDown('L')
        assert(ChatFrame1EditBox:GetText() == 'ghbdsn')
        """
    )


if __name__ == "__main__":
    test_en_to_uk_and_uk_to_en()
    test_preserves_links_icons_and_slash_commands()
    test_hotkey_hook_and_setting_toggle()
    print("Chat layout switcher checks passed")
