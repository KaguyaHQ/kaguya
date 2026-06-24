defmodule Kaguya.Sync.VndbStorefrontMapper do
  @moduledoc """
  Maps VNDB extlink `{site, value}` pairs to full URLs and human-readable labels.
  """

  @doc "Build a full URL from a VNDB extlink site + value pair."
  # Storefronts — release sites
  def build_url("steam", value), do: "https://store.steampowered.com/app/#{value}/"
  def build_url("gog", value), do: "https://www.gog.com/en/game/#{value}"

  def build_url("itch", value) do
    case String.split(value, "/", parts: 2) do
      [user, game] -> "https://#{user}.itch.io/#{game}"
      _ -> "https://#{value}.itch.io"
    end
  end

  def build_url("dlsite", value),
    do: "https://www.dlsite.com/home/work/=/product_id/#{value}.html"

  def build_url("dlsiteen", value),
    do: "https://www.dlsite.com/eng/work/=/product_id/#{value}.html"

  def build_url("dmm", value), do: "https://#{value}"
  def build_url("getchu", value), do: "http://www.getchu.com/soft.phtml?id=#{value}"
  def build_url("getchudl", value), do: "http://dl.getchu.com/i/item#{value}"
  def build_url("gyutto", value), do: "https://gyutto.com/i/item#{value}"

  def build_url("digiket", value),
    do: "https://www.digiket.com/work/show/_data/ID=ITM#{pad_int(value, 7)}/"

  def build_url("melonjp", value),
    do: "https://www.melonbooks.co.jp/detail/detail.php?product_id=#{value}"

  def build_url("melon", value),
    do:
      "https://www.melonbooks.com/index.php?main_page=product_info&products_id=IT#{pad_int(value, 10)}"

  def build_url("booth", value), do: "https://booth.pm/en/items/#{value}"
  # JAST moved from jastusa.com to jaststore.com in 2026. The short
  # `/games/<code>` form resolves directly to the current product page.
  def build_url("jastusa", value), do: "https://jaststore.com/games/#{value}"
  def build_url("jlist", value), do: "https://jlist.com/shop/product/#{value}"

  def build_url("mg", value),
    do: "https://www.mangagamer.com/r18/detail.php?product_code=#{value}"

  def build_url("fakku", value), do: "https://www.fakku.net/games/#{value}"
  def build_url("nutaku", value), do: "https://www.nutaku.net/games/#{value}/"
  def build_url("johren", value), do: "https://www.johren.games/games/download/#{value}/"
  def build_url("denpa", value), do: "https://denpasoft.com/product/#{value}/"
  def build_url("kagura", value), do: "https://www.kaguragames.com/product/#{value}/"
  def build_url("gamejolt", value), do: "https://gamejolt.com/games/vn/#{value}"
  def build_url("freem", value), do: "https://www.freem.ne.jp/win/game/#{value}"
  def build_url("freegame", value), do: "https://freegame-mugen.jp/#{value}.html"
  def build_url("novelgam", value), do: "https://novelgame.jp/games/show/#{value}"
  def build_url("googplay", value), do: "https://play.google.com/store/apps/details?id=#{value}"
  def build_url("appstore", value), do: "https://apps.apple.com/app/id#{value}"
  def build_url("nintendo", value), do: "https://www.nintendo.com/store/products/#{value}/"
  def build_url("nintendo_jp", value), do: "https://store-jp.nintendo.com/item/software/D#{value}"
  def build_url("nintendo_hk", value), do: "https://store.nintendo.com.hk/#{value}"

  def build_url("playstation_na", value),
    do: "https://store.playstation.com/en-us/product/#{value}"

  def build_url("playstation_eu", value),
    do: "https://store.playstation.com/en-gb/product/#{value}"

  def build_url("playstation_jp", value),
    do: "https://store.playstation.com/ja-jp/product/#{value}"

  def build_url("playstation_hk", value),
    do: "https://store.playstation.com/en-hk/product/#{value}"

  def build_url("playasia", value), do: "https://www.play-asia.com/13/70#{value}"

  def build_url("toranoana", value),
    do: "https://ec.toranoana.shop/tora/ec/item/#{pad_int(value, 12)}/"

  def build_url("animateg", value), do: "https://www.animategames.jp/home/detail/#{value}"
  def build_url("erotrail", value), do: "http://erogetrailers.com/soft/#{value}"

  def build_url("egs", value),
    do: "https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/game.php?game=#{value}"

  def build_url("renai", value), do: "https://renai.us/game/#{value}"
  def build_url("encubed", value), do: "http://novelnews.net/tag/#{value}/"
  def build_url("patreon", value), do: "https://www.patreon.com/#{value}"
  def build_url("patreonp", value), do: "https://www.patreon.com/posts/#{value}"
  def build_url("substar", value), do: "https://subscribestar.#{value}"
  def build_url("website", value), do: value
  # Discord invite/server URLs vary in shape (discord.gg/X, discord.com/invite/Y,
  # custom subdomains, etc.) so the value is stored as the full URL — we pass
  # it through verbatim, same as `website`.
  def build_url("discord", value), do: value
  # Social / producer / staff sites
  def build_url("twitter", value), do: "https://x.com/#{value}"
  def build_url("youtube", value), do: "https://www.youtube.com/@#{value}"
  def build_url("bsky", value), do: "https://bsky.app/profile/#{value}"
  def build_url("instagram", value), do: "https://www.instagram.com/#{value}/"
  def build_url("facebook", value), do: "https://www.facebook.com/#{value}"
  def build_url("tumblr", value), do: "https://#{value}.tumblr.com/"
  def build_url("pixiv", value), do: "https://www.pixiv.net/member.php?id=#{value}"
  def build_url("vk", value), do: "https://vk.com/#{value}"
  def build_url("deviantar", value), do: "https://www.deviantart.com/#{value}"
  def build_url("kofi", value), do: "https://ko-fi.com/#{value}"
  def build_url("steam_curator", value), do: "https://store.steampowered.com/curator/#{value}"
  def build_url("itch_dev", value), do: "https://#{value}.itch.io/"
  def build_url("booth_pub", value), do: "https://#{value}.booth.pm/"
  def build_url("fanbox", value), do: "https://#{value}.fanbox.cc/"
  def build_url("fantia", value), do: "https://fantia.jp/fanclubs/#{value}"
  def build_url("cien", value), do: "https://ci-en.dlsite.com/creator/#{value}"
  def build_url("scloud", value), do: "https://soundcloud.com/#{value}"
  def build_url("nijie", value), do: "https://nijie.info/members.php?id=#{value}"
  def build_url("bilibili", value), do: "https://space.bilibili.com/#{value}"
  def build_url("weibo", value), do: "https://weibo.com/u/#{value}"
  def build_url("boosty", value), do: "https://boosty.to/#{value}"
  def build_url("afdian", value), do: "https://afdian.com/a/#{value}"
  # Database / reference sites
  def build_url("anidb", value), do: "https://anidb.net/cr#{value}"
  def build_url("anison", value), do: "http://anison.info/data/person/#{value}.html"
  def build_url("bgmtv", value), do: "https://bgm.tv/person/#{value}"
  def build_url("discogs", value), do: "https://www.discogs.com/artist/#{value}"

  def build_url("egs_creator", value),
    do: "https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/creater.php?creater=#{value}"

  def build_url("imdb", value), do: "https://www.imdb.com/name/nm#{pad_int(value, 7)}"
  def build_url("mbrainz", value), do: "https://musicbrainz.org/artist/#{value}"
  def build_url("vgmdb", value), do: "https://vgmdb.net/artist/#{value}"
  def build_url("vgmdb_org", value), do: "https://vgmdb.net/org/#{value}"
  def build_url("vndb", value), do: "https://vndb.org/#{value}"
  def build_url("wikidata", value), do: "https://www.wikidata.org/wiki/Q#{value}"
  def build_url("wp", value), do: "https://en.wikipedia.org/wiki/#{value}"
  def build_url("mobygames", value), do: "https://www.mobygames.com/person/#{value}"
  def build_url("mobygames_comp", value), do: "https://www.mobygames.com/company/#{value}"
  def build_url("gamefaqs_comp", value), do: "https://gamefaqs.gamespot.com/company/#{value}-"
  # Wikidata-derived sites (Wikipedia sitelinks + property lookups)
  # Wikipedia/wiki URLs: spaces → underscores, keep slashes and unicode as-is
  def build_url("enwiki", value), do: "https://en.wikipedia.org/wiki/#{wiki_encode(value)}"
  def build_url("jawiki", value), do: "https://ja.wikipedia.org/wiki/#{wiki_encode(value)}"
  def build_url("mobygames_game", value), do: "https://www.mobygames.com/game/#{value}/"
  def build_url("gamefaqs_game", value), do: "https://gamefaqs.gamespot.com/-/#{value}-"
  def build_url("igdb_game", value), do: "https://www.igdb.com/games/#{value}"
  def build_url("howlongtobeat", value), do: "https://howlongtobeat.com/game/#{value}"

  def build_url("pcgamingwiki", value),
    do: "https://www.pcgamingwiki.com/wiki/#{wiki_encode(value)}"

  def build_url("acdb_source", value),
    do: "https://www.animecharactersdatabase.com/source.php?id=#{value}"

  def build_url("vgmdb_product", value), do: "https://vgmdb.net/product/#{value}"
  def build_url("indiedb_game", value), do: "https://www.indiedb.com/games/#{value}"
  def build_url(_site, _value), do: nil

  # Zero-pad a numeric string to the given width
  defp pad_int(value, width) do
    String.pad_leading(to_string(value), width, "0")
  end

  # Wikipedia-style URL encoding: spaces → underscores, everything else as-is.
  # Sitelink values from Wikidata are already valid article titles.
  defp wiki_encode(value) do
    String.replace(value, " ", "_")
  end

  @doc "Get a human-readable label for a storefront site."
  def label("steam"), do: "Steam"
  def label("gog"), do: "GOG"
  def label("itch"), do: "itch.io"
  def label("dlsite"), do: "DLsite"
  def label("dlsiteen"), do: "DLsite (EN)"
  def label("dmm"), do: "DMM"
  def label("getchu"), do: "Getchu"
  def label("getchudl"), do: "Getchu DL"
  def label("gyutto"), do: "Gyutto"
  def label("digiket"), do: "DiGiket"
  def label("melonjp"), do: "Melonbooks"
  def label("melon"), do: "Melonbooks"
  def label("booth"), do: "BOOTH"
  def label("jastusa"), do: "JAST USA"
  def label("jlist"), do: "J-List"
  def label("mg"), do: "MangaGamer"
  def label("fakku"), do: "FAKKU"
  def label("nutaku"), do: "Nutaku"
  def label("johren"), do: "Johren"
  def label("denpa"), do: "Denpasoft"
  def label("kagura"), do: "Kagura Games"
  def label("gamejolt"), do: "Game Jolt"
  def label("freem"), do: "Freem!"
  def label("freegame"), do: "Free Game Mugen"
  def label("novelgam"), do: "NovelGame"
  def label("googplay"), do: "Google Play"
  def label("appstore"), do: "App Store"
  def label("nintendo"), do: "Nintendo eShop"
  def label("nintendo_jp"), do: "Nintendo eShop (JP)"
  def label("nintendo_hk"), do: "Nintendo eShop (HK)"
  def label("playstation_na"), do: "PlayStation Store (NA)"
  def label("playstation_eu"), do: "PlayStation Store (EU)"
  def label("playstation_jp"), do: "PlayStation Store (JP)"
  def label("playstation_hk"), do: "PlayStation Store (HK)"
  def label("playasia"), do: "Play-Asia"
  def label("toranoana"), do: "Toranoana"
  def label("animateg"), do: "Animate Games"
  def label("erotrail"), do: "ErogeTrailers"
  def label("egs"), do: "ErogameScape"
  def label("renai"), do: "Ren'Ai Archive"
  def label("encubed"), do: "encubed"
  def label("patreon"), do: "Patreon"
  def label("patreonp"), do: "Patreon"
  def label("substar"), do: "SubscribeStar"
  def label("website"), do: "Website"
  def label("twitter"), do: "X (Twitter)"
  def label("youtube"), do: "YouTube"
  def label("bsky"), do: "Bluesky"
  def label("instagram"), do: "Instagram"
  def label("facebook"), do: "Facebook"
  def label("tumblr"), do: "Tumblr"
  def label("pixiv"), do: "pixiv"
  def label("vk"), do: "VK"
  def label("deviantar"), do: "DeviantArt"
  def label("kofi"), do: "Ko-fi"
  def label("steam_curator"), do: "Steam"
  def label("itch_dev"), do: "itch.io"
  def label("booth_pub"), do: "BOOTH"
  def label("fanbox"), do: "pixiv FANBOX"
  def label("fantia"), do: "Fantia"
  def label("cien"), do: "Ci-en"
  def label("scloud"), do: "SoundCloud"
  def label("nijie"), do: "Nijie"
  def label("bilibili"), do: "Bilibili"
  def label("weibo"), do: "Weibo"
  def label("boosty"), do: "Boosty"
  def label("afdian"), do: "Afdian"
  # Database / reference sites
  def label("anidb"), do: "AniDB"
  def label("anison"), do: "Anison"
  def label("bgmtv"), do: "Bangumi"
  def label("discogs"), do: "Discogs"
  def label("egs_creator"), do: "ErogameScape"
  def label("imdb"), do: "IMDb"
  def label("mbrainz"), do: "MusicBrainz"
  def label("vgmdb"), do: "VGMdb"
  def label("vgmdb_org"), do: "VGMdb"
  def label("vndb"), do: "VNDB"
  def label("wikidata"), do: "Wikidata"
  def label("wp"), do: "Wikipedia"
  def label("mobygames"), do: "MobyGames"
  def label("mobygames_comp"), do: "MobyGames"
  def label("gamefaqs_comp"), do: "GameFAQs"
  # Wikidata-derived sites
  def label("enwiki"), do: "Wikipedia (en)"
  def label("jawiki"), do: "Wikipedia (ja)"
  def label("mobygames_game"), do: "MobyGames"
  def label("gamefaqs_game"), do: "GameFAQs"
  def label("igdb_game"), do: "IGDB"
  def label("howlongtobeat"), do: "HowLongToBeat"
  def label("pcgamingwiki"), do: "PCGamingWiki"
  def label("acdb_source"), do: "ACDB"
  def label("vgmdb_product"), do: "VGMdb"
  def label("indiedb_game"), do: "IndieDB"
  def label("discord"), do: "Discord"
  def label(site), do: site

  @doc "Get a human-readable short label for a VNDB platform code."
  def platform_label("win"), do: "Win"
  def platform_label("lin"), do: "Lin"
  def platform_label("mac"), do: "Mac"
  def platform_label("web"), do: "Web"
  def platform_label("and"), do: "Android"
  def platform_label("ios"), do: "iOS"
  def platform_label("swi"), do: "Switch"
  def platform_label("sw2"), do: "Switch 2"
  def platform_label("ps1"), do: "PS1"
  def platform_label("ps2"), do: "PS2"
  def platform_label("ps3"), do: "PS3"
  def platform_label("ps4"), do: "PS4"
  def platform_label("ps5"), do: "PS5"
  def platform_label("psp"), do: "PSP"
  def platform_label("psv"), do: "Vita"
  def platform_label("xb1"), do: "XB1"
  def platform_label("xb3"), do: "XBS"
  def platform_label("xbo"), do: "Xbox"
  def platform_label("xxs"), do: "XSX"
  def platform_label("x1s"), do: "XB1S"
  def platform_label("nds"), do: "DS"
  def platform_label("n3d"), do: "3DS"
  def platform_label("wii"), do: "Wii"
  def platform_label("wiu"), do: "Wii U"
  def platform_label("nes"), do: "NES"
  def platform_label("sfc"), do: "SNES"
  def platform_label("gba"), do: "GBA"
  def platform_label("gbc"), do: "GBC"
  def platform_label("mob"), do: "Mobile"
  def platform_label("dos"), do: "DOS"
  def platform_label("sat"), do: "Saturn"
  def platform_label("drc"), do: "DC"
  def platform_label("pce"), do: "PCE"
  def platform_label("pcf"), do: "PC-FX"
  def platform_label("smd"), do: "MD"
  def platform_label("scd"), do: "Sega CD"
  def platform_label("fm7"), do: "FM-7"
  def platform_label("fm8"), do: "FM-8"
  def platform_label("fmt"), do: "FMT"
  def platform_label("msx"), do: "MSX"
  def platform_label("p88"), do: "PC-88"
  def platform_label("p98"), do: "PC-98"
  def platform_label("x68"), do: "X68K"
  def platform_label("bdp"), do: "BD"
  def platform_label("dvd"), do: "DVD"
  def platform_label("tdo"), do: "3DO"
  def platform_label("vnd"), do: "VNDS"
  def platform_label("oth"), do: "Other"
  def platform_label(code), do: String.upcase(code)

  @platform_order %{
    "win" => 0,
    "mac" => 1,
    "lin" => 2,
    "web" => 3,
    "and" => 4,
    "ios" => 5,
    "swi" => 10,
    "sw2" => 11,
    "ps5" => 20,
    "ps4" => 21,
    "ps3" => 22,
    "ps2" => 23,
    "ps1" => 24,
    "psv" => 25,
    "psp" => 26,
    "xb3" => 30,
    "xxs" => 31,
    "xb1" => 32,
    "x1s" => 33,
    "xbo" => 34,
    "n3d" => 40,
    "nds" => 41,
    "wiu" => 42,
    "wii" => 43,
    "mob" => 50
  }

  @doc "Get a human-readable label for a VNDB media type code."
  def media_label("in"), do: "Internet download"
  def media_label("cd"), do: "CD"
  def media_label("dvd"), do: "DVD"
  def media_label("blr"), do: "Blu-ray"
  def media_label("flp"), do: "Floppy"
  def media_label("mrt"), do: "Cartridge"
  def media_label("mem"), do: "Memory card"
  def media_label("umd"), do: "UMD"
  def media_label("nod"), do: "Nintendo optical disc"
  def media_label("gdr"), do: "GD-ROM"
  def media_label("dc"), do: "LaserDisc"
  def media_label("cas"), do: "Cassette tape"
  def media_label("otc"), do: "Other"
  def media_label(code), do: code

  @doc "Sort platform codes in display order (Win, Mac, Lin first, then modern consoles)."
  def sort_platforms(platforms) do
    Enum.sort_by(platforms, &Map.get(@platform_order, &1, 99))
  end

  @available_on_label %{
    "steam" => "Steam",
    "itch" => "itch.io",
    "gog" => "GOG",
    "jast" => "JAST",
    "mangagamer" => "MangaGamer",
    "denpasoft" => "Denpasoft",
    "johren" => "Johren",
    "dlsite" => "DLsite",
    "nintendo" => "Nintendo eShop",
    "playstation" => "PlayStation Store",
    "appstore" => "App Store",
    "googplay" => "Google Play",
    "booth" => "BOOTH",
    "freem" => "Freem!",
    "novelgam" => "NovelGame",
    "freegame" => "Free Game Mugen",
    "gamejolt" => "Game Jolt",
    "getchu" => "Getchu",
    "digiket" => "DiGiket",
    "gyutto" => "Gyutto",
    "dmm" => "DMM",
    "melonbooks" => "Melonbooks",
    "toranoana" => "Toranoana",
    "animateg" => "Animate Games",
    "playasia" => "Play-Asia",
    "jlist" => "J-List",
    "kagura" => "Kagura Games",
    "fakku" => "FAKKU",
    "nutaku" => "Nutaku",
    "patreon" => "Patreon"
  }

  @available_on_order %{
    "steam" => 0,
    "itch" => 1,
    "gog" => 2,
    "jast" => 3,
    "mangagamer" => 4,
    "denpasoft" => 5,
    "johren" => 6,
    "dlsite" => 7,
    "nintendo" => 8,
    "playstation" => 9,
    "appstore" => 10,
    "googplay" => 11,
    "booth" => 20,
    "freem" => 21,
    "novelgam" => 22,
    "freegame" => 23,
    "gamejolt" => 24,
    "getchu" => 25,
    "digiket" => 26,
    "gyutto" => 27,
    "dmm" => 28,
    "melonbooks" => 29,
    "toranoana" => 30,
    "animateg" => 31,
    "playasia" => 32,
    "jlist" => 33,
    "kagura" => 34,
    "fakku" => 35,
    "nutaku" => 36,
    "patreon" => 40
  }

  @primary_available_on_families MapSet.new([
                                   "steam",
                                   "itch",
                                   "gog",
                                   "jast",
                                   "mangagamer",
                                   "denpasoft",
                                   "johren",
                                   "dlsite",
                                   "nintendo",
                                   "playstation",
                                   "appstore",
                                   "googplay"
                                 ])

  @doc "Returns the storefront family used by the VN-page Available on row."
  def available_on_family("steam"), do: "steam"
  def available_on_family("itch"), do: "itch"
  def available_on_family("gog"), do: "gog"
  def available_on_family("jastusa"), do: "jast"
  def available_on_family("mg"), do: "mangagamer"
  def available_on_family("denpa"), do: "denpasoft"
  def available_on_family("johren"), do: "johren"
  def available_on_family("dlsite"), do: "dlsite"
  def available_on_family("dlsiteen"), do: "dlsite"
  def available_on_family("nintendo"), do: "nintendo"
  def available_on_family("nintendo_jp"), do: "nintendo"
  def available_on_family("nintendo_hk"), do: "nintendo"
  def available_on_family("playstation_na"), do: "playstation"
  def available_on_family("playstation_eu"), do: "playstation"
  def available_on_family("playstation_jp"), do: "playstation"
  def available_on_family("playstation_hk"), do: "playstation"
  def available_on_family("appstore"), do: "appstore"
  def available_on_family("googplay"), do: "googplay"
  def available_on_family("booth"), do: "booth"
  def available_on_family("freem"), do: "freem"
  def available_on_family("novelgam"), do: "novelgam"
  def available_on_family("freegame"), do: "freegame"
  def available_on_family("gamejolt"), do: "gamejolt"
  def available_on_family("getchu"), do: "getchu"
  def available_on_family("getchudl"), do: "getchu"
  def available_on_family("digiket"), do: "digiket"
  def available_on_family("gyutto"), do: "gyutto"
  def available_on_family("dmm"), do: "dmm"
  def available_on_family("melonjp"), do: "melonbooks"
  def available_on_family("melon"), do: "melonbooks"
  def available_on_family("toranoana"), do: "toranoana"
  def available_on_family("animateg"), do: "animateg"
  def available_on_family("playasia"), do: "playasia"
  def available_on_family("jlist"), do: "jlist"
  def available_on_family("kagura"), do: "kagura"
  def available_on_family("fakku"), do: "fakku"
  def available_on_family("nutaku"), do: "nutaku"
  def available_on_family("patreon"), do: "patreon"
  def available_on_family("patreonp"), do: "patreon"
  def available_on_family(_site), do: nil

  @doc "Returns true when a VNDB release extlink site should be shown in Available on."
  def available_on_storefront?(site), do: not is_nil(available_on_family(site))

  @doc "Canonical label used by the VN-page Available on row."
  def available_on_label(family), do: Map.fetch!(@available_on_label, family)

  @doc "Display order used by the VN-page Available on row."
  def available_on_sort_key(family), do: Map.get(@available_on_order, family, 999)

  @doc "True when the storefront family is popular/direct enough to show ahead of fallback stores."
  def primary_available_on_family?(family),
    do: MapSet.member?(@primary_available_on_families, family)

  @doc "All raw VNDB extlink site codes that qualify for the Available on row."
  def available_on_sites do
    @available_on_label
    |> Map.keys()
    |> Enum.flat_map(fn
      "jast" -> ["jastusa"]
      "mangagamer" -> ["mg"]
      "denpasoft" -> ["denpa"]
      "dlsite" -> ["dlsite", "dlsiteen"]
      "nintendo" -> ["nintendo", "nintendo_jp", "nintendo_hk"]
      "playstation" -> ["playstation_na", "playstation_eu", "playstation_jp", "playstation_hk"]
      "getchu" -> ["getchu", "getchudl"]
      "melonbooks" -> ["melonjp", "melon"]
      "toranoana" -> ["toranoana"]
      "animateg" -> ["animateg"]
      "patreon" -> ["patreon", "patreonp"]
      family -> [family]
    end)
    |> Enum.uniq()
  end

  @doc "Normalizes stored storefront URLs for display where the upstream host moved."
  def canonical_available_on_url("jastusa", "https://jastusa.com" <> path) do
    "https://jaststore.com" <> path
  end

  def canonical_available_on_url(_site, url), do: url
end
