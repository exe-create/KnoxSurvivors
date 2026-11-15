-- Drives the real KnoxText helper. A language that lacks a key, or a translator
-- that throws, must still show English wording rather than a raw key.
local savedTranslator = getText
local T = assert(KnoxText, 'the text helper loads')
getText = function(key) return key end
assert(T.get('IGUI_KS_Absent', 'English wording') == 'English wording',
    'a missing key falls back to English wording')
getText = function(key) return 'translated wording' end
assert(T.get('IGUI_KS_Present', 'English wording') == 'translated wording',
    'a present key uses the translation')
getText = function() error('translator unavailable') end
assert(T.get('IGUI_KS_Broken', 'English wording') == 'English wording',
    'a translator error falls back to English wording')
getText = function(key) return key end
assert(T.format('IGUI_KS_Absent', 'Have %1 saw logs', 'Mara') == 'Have Mara saw logs',
    'a missing key still substitutes one name')
getText = function(key) return 'Lass %1 Staemme saegen' end
assert(T.format('IGUI_KS_HaveSawLogs', 'Have %1 saw logs', 'Mara')
    == 'Lass Mara Staemme saegen', 'a translated key substitutes one name')

getText = savedTranslator
