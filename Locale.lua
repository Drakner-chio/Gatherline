-- Gatherline: the words. Code is written in English; L["English text"] gives
-- the text in the game's language when there's a translation, else the English.
-- Translations are keyed by the whole English text (format codes included).

local ADDON, ns = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- Only the game's own language is loaded
local locale = GetLocale and GetLocale() or "enUS"
ns.LOCALE = locale

-- Locale_deDE.lua fills this before anything is drawn
ns.TRANSLATIONS = ns.TRANSLATIONS or {}

function ns.UseTranslations()
    local t = ns.TRANSLATIONS[locale]
    if not t then return end
    for k, v in pairs(t) do rawset(L, k, v) end
end
