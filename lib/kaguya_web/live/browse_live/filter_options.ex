defmodule KaguyaWeb.BrowseLive.FilterOptions do
  @moduledoc false

  def lengths do
    [
      {"Any", "", nil},
      {"Short", "short", "< 10 hours"},
      {"Medium", "medium", "10-30 hours"},
      {"Long", "long", "30-50 hours"},
      {"Very Long", "very_long", "50+ hours"}
    ]
  end

  def platforms do
    [
      {"Windows", "win"},
      {"Android", "and"},
      {"Nintendo Switch", "swi"},
      {"macOS", "mac"},
      {"Linux", "lin"},
      {"PlayStation Vita", "psv"},
      {"iOS", "ios"},
      {"PlayStation Portable", "psp"},
      {"PlayStation 4", "ps4"},
      {"Web/Browser", "web"},
      {"PlayStation 3", "ps3"},
      {"PlayStation 2", "ps2"},
      {"PlayStation 5", "ps5"},
      {"Nintendo DS", "nds"},
      {"Xbox Series X/S", "xxs"},
      {"Xbox One", "xbo"},
      {"Xbox 360", "x36"},
      {"PlayStation 1", "ps1"},
      {"Switch 2", "sw2"},
      {"PC-98", "p98"},
      {"PC-88", "p88"},
      {"Sega Saturn", "sat"},
      {"Dreamcast", "drc"},
      {"DOS", "dos"},
      {"MSX", "msx"},
      {"Nintendo 3DS", "n3d"},
      {"Game Boy Advance", "gba"},
      {"Wii", "wii"},
      {"PC Engine", "pce"},
      {"FM Towns", "fmd"},
      {"Super Famicom", "sfc"},
      {"NES", "nes"},
      {"Game Boy Color", "gbc"},
      {"PC-FX", "pcf"},
      {"X68000", "x68"},
      {"FM-7", "fm7"},
      {"X1 Super", "x1s"},
      {"Sega CD", "scd"},
      {"Sega Genesis", "smd"},
      {"Wii U", "wiu"},
      {"FM-8", "fm8"},
      {"3DO", "tdo"},
      {"Amiga", "amg"},
      {"Mobile (legacy)", "mob"},
      {"Blu-ray Player", "bdp"},
      {"VN.com", "vnd"},
      {"DVD Player", "dvd"},
      {"Other", "oth"}
    ]
  end

  def languages do
    [
      {"日本語", "ja"},
      {"English", "en"},
      {"简体中文", "zh-Hans"},
      {"Русский", "ru"},
      {"Español", "es"},
      {"한국어", "ko"},
      {"繁體中文", "zh-Hant"},
      {"Português (BR)", "pt-br"},
      {"Tiếng Việt", "vi"},
      {"Italiano", "it"},
      {"Français", "fr"},
      {"Bahasa Indonesia", "id"},
      {"Deutsch", "de"},
      {"Polski", "pl"},
      {"Türkçe", "tr"},
      {"Українська", "uk"},
      {"العربية", "ar"},
      {"Magyar", "hu"},
      {"ไทย", "th"},
      {"Català", "ca"},
      {"Čeština", "cs"},
      {"Português (PT)", "pt-pt"},
      {"Suomi", "fi"},
      {"Nederlands", "nl"},
      {"Latviešu", "lv"},
      {"Svenska", "sv"},
      {"Bahasa Melayu", "ms"},
      {"Norsk", "no"},
      {"Български", "bg"},
      {"Euskara", "eu"},
      {"Ελληνικά", "el"},
      {"עברית", "he"},
      {"Dansk", "da"},
      {"فارسی", "fa"},
      {"Gaeilge", "ga"},
      {"Slovenčina", "sk"},
      {"Română", "ro"},
      {"हिन्दी", "hi"},
      {"தமிழ்", "ta"},
      {"Eesti", "et"},
      {"Esperanto", "eo"},
      {"Беларуская", "be"},
      {"Slovenščina", "sl"},
      {"Gàidhlig", "gd"},
      {"Galego", "gl"},
      {"Lietuvių", "lt"},
      {"Македонски", "mk"},
      {"Bosanski", "bs"},
      {"Latina", "la"},
      {"Hrvatski", "hr"},
      {"ᏣᎳᎩ", "ck"},
      {"Қазақша", "kk"},
      {"ᐃᓄᒃᑎᑐᑦ", "iu"},
      {"Српски", "sr"},
      {"اردو", "ur"}
    ]
  end

  def original_languages do
    languages()
    |> Enum.take(32)
  end

  def engines do
    [
      {"Ren'Py", "Ren'Py"},
      {"KiriKiri", "KiriKiri"},
      {"TyranoScript", "TyranoScript"},
      {"Unity", "Unity"},
      {"LiveMaker", "LiveMaker"},
      {"NScripter", "NScripter"},
      {"RPG Maker", "RPG Maker"},
      {"YU-RIS", "YU-RIS"},
      {"Flash Player", "Flash Player"},
      {"Godot", "Godot"},
      {"Artemis Engine", "Artemis Engine"},
      {"Dorian Engine", "Dorian Engine"},
      {"Macromedia Director", "Macromedia Director"},
      {"Wolf RPG Editor", "Wolf RPG Editor"},
      {"Shiina Rio", "Shiina Rio"},
      {"Cocos2d", "Cocos2d"},
      {"Visual Novel Maker", "Visual Novel Maker"},
      {"Majiro", "Majiro"},
      {"RealLive", "RealLive"},
      {"System-NNN", "System-NNN"},
      {"BGI/Ethornell", "BGI/Ethornell"},
      {"GameMaker", "GameMaker"},
      {"Light.vn", "Light.vn"},
      {"Comic Maker", "Comic Maker"},
      {"Yuuki! Novel", "Yuuki! Novel"},
      {"Twine", "Twine"},
      {"SiglusEngine", "SiglusEngine"},
      {"CatSystem2", "CatSystem2"},
      {"AVG32", "AVG32"},
      {"Bruns", "Bruns"},
      {"Comic Maker 2", "Comic Maker 2"},
      {"QLIE", "QLIE"},
      {"NeXAS", "NeXAS"},
      {"EntisGLS", "EntisGLS"},
      {"codeX RScript", "codeX RScript"},
      {"ADV98V", "ADV98V"},
      {"KaGuYa", "KaGuYa"},
      {"SaiSys", "SaiSys"},
      {"Marble", "Marble"},
      {"ADV Player HD", "ADV Player HD"},
      {"Malie", "Malie"},
      {"AST", "AST"},
      {"AliceSoft System4.X", "AliceSoft System4.X"},
      {"Ikura GDL", "Ikura GDL"},
      {"AliceSoft System3.X", "AliceSoft System3.X"},
      {"Hot Soup Processor", "Hot Soup Processor"},
      {"Luca System", "Luca System"},
      {"MAGES. Engine", "MAGES. Engine"},
      {"ExHibit", "ExHibit"},
      {"Adobe AIR", "Adobe AIR"}
    ]
  end

  def stores do
    [
      {"Steam", "steam"},
      {"itch.io", "itch"},
      {"DLsite", "dlsite"},
      {"DLsite (EN)", "dlsiteen"},
      {"DMM", "dmm"},
      {"Getchu", "getchu"},
      {"DiGiket", "digiket"},
      {"Gyutto", "gyutto"},
      {"Play-Asia", "playasia"},
      {"Google Play", "googplay"},
      {"App Store", "appstore"},
      {"Patreon", "patreon"},
      {"Freem!", "freem"},
      {"Melonbooks", "melonjp"},
      {"BOOTH", "booth"},
      {"GOG", "gog"},
      {"MangaGamer", "mg"},
      {"JAST USA", "jastusa"},
      {"Denpasoft", "denpa"},
      {"Nutaku", "nutaku"},
      {"FAKKU", "fakku"},
      {"Kagura Games", "kagura"}
    ]
  end

  def free_stores do
    [
      {"itch.io", "itch"},
      {"Steam", "steam"}
    ]
  end

  def label(options, value) do
    value = to_string(value)

    Enum.find_value(options, value, fn
      {label, ^value} -> label
      {label, ^value, _description} -> label
      _option -> nil
    end)
  end
end
