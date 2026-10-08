import SwiftUI
import AppKit
import DuoUpdaterCore

/// A Homebrew formula's icon, in three layers:
/// 1. a bundled logo for a common formula (``FormulaLogo``), on its brand colour;
/// 2. otherwise the formula's own icon, fetched from its homepage or its GitHub
///    owner's avatar (`BrewFormulaIconService`), drawn as published;
/// 3. otherwise, and until that arrives, the Homebrew logo.
struct FormulaIcon: View {
    let name: String
    let size: CGFloat

    @State private var fetched: NSImage?

    private var logo: FormulaLogo? { FormulaLogo.lookup(name) }

    var body: some View {
        Group {
            if let logo {
                LogoTile(tint: logo.tint, size: size) {
                    Image(logo.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.6, height: size * 0.6)
                        .foregroundStyle(logo.tint)
                }
            } else if let image = fetched ?? FormulaIconMemoryCache.shared.image(for: name) {
                // A site's own icon is usually a full-colour square: drawn as is,
                // not tinted, on a neutral tile.
                LogoTile(tint: Color(nsColor: .labelColor), size: size) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size * 0.72, height: size * 0.72)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
                }
            } else {
                LogoTile(tint: FormulaLogo.homebrew.tint, size: size) {
                    Image(FormulaLogo.homebrew.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.6, height: size * 0.6)
                        .foregroundStyle(FormulaLogo.homebrew.tint)
                }
            }
        }
        .task(id: name) {
            guard logo == nil, fetched == nil,
                  FormulaIconMemoryCache.shared.image(for: name) == nil,
                  let data = await BrewFormulaIconService.shared.icon(forFormula: name)
            else { return }
            fetched = FormulaIconMemoryCache.shared.store(data, for: name)
        }
    }
}

/// Decoded fetched icons by formula name, so a row scrolled back into view, or
/// the detail header beside it, paints at once instead of flashing the Homebrew
/// logo. Icons are at most 128 px, so the count limit is the bound that matters.
final class FormulaIconMemoryCache: @unchecked Sendable {
    static let shared = FormulaIconMemoryCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 300 }

    func image(for name: String) -> NSImage? { cache.object(forKey: name as NSString) }

    func store(_ data: Data, for name: String) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

/// A bundled formula logo: an asset in `Assets.xcassets/FormulaLogos` (or a
/// CLI tool's in `CLILogos`, for the same project) and its brand colour.
///
/// All are Simple Icons 16.34.0, chosen from the 400 most-installed formulae
/// (Homebrew's 365-day install-on-request analytics, 2026-10-08) where the
/// icon's own source is the formula's project: the same domain or GitHub
/// organisation as its homepage, or a stated reason where the project moved.
/// Name-alike icons of other things were refused (boost → Boost Mobile, make →
/// Make.com; for bat, the Basic Attention Token icon, while sharkdp/bat's own
/// mark, sourced from github.com/sharkdp, is the one kept), as was CocoaPods'
/// (non-commercial licence). `gh` takes GitHub's mark (its homepage is cli.github.com). Icons
/// under a licence other than CC0 say so beside their entry.
struct FormulaLogo {
    let asset: String
    let hex: UInt32

    /// The table's key for `name`: a tap's prefix and an `@version` dropped, so
    /// `python@3.13` and `oven-sh/bun/bun` find `python` and `bun`.
    static func lookup(_ name: String) -> FormulaLogo? {
        let short = name.split(separator: "/").last.map(String.init) ?? name
        let base = short.split(separator: "@").first.map(String.init) ?? short
        return table[base].map { FormulaLogo(asset: $0.asset, hex: $0.hex) }
    }

    static let homebrew = FormulaLogo(asset: "brew-homebrew", hex: 0xFBB040)

    private static let table: [String: (asset: String, hex: UInt32)] = [
        "node":        ("brew-nodedotjs", 0x5FA04E),
        "uv":          ("cli-uv", 0xDE5FE9),
        "ffmpeg":      ("brew-ffmpeg", 0x007808),
        "git":         ("brew-git", 0xF03C2E),  // CC-BY-3.0
        "cmake":       ("brew-cmake", 0x064F8C),
        "go":          ("brew-go", 0x00ADD8),
        "python":      ("brew-python", 0x3776AB),
        "docker":      ("brew-docker", 0x2496ED),
        "openssl":     ("brew-openssl", 0x721412),
        "ollama":      ("brew-ollama", 0x000000),
        "pipx":        ("brew-pipx", 0x2CFFAA),
        "pnpm":        ("brew-pnpm", 0xF69220),
        "tmux":        ("brew-tmux", 0x1BB91F),
        "nvm":         ("brew-nvm", 0xF4DD4B),
        "helm":        ("brew-helm", 0x0F1689),
        "neovim":      ("brew-neovim", 0x57A143),  // CC-BY-SA-3.0
        "just":        ("brew-just", 0x000000),
        "pandoc":      ("brew-pandoc", 0x4093DA),  // CC-BY-SA-4.0
        "opencode":    ("cli-opencode", 0x000000),
        "redis":       ("brew-redis", 0xFF4438),
        "openjdk":     ("brew-openjdk", 0x000000),  // BSD-3-Clause
        "rust":        ("cli-rust", 0x000000),  // CC-BY-SA-4.0
        "llvm":        ("brew-llvm", 0x262D3A),
        "curl":        ("brew-curl", 0x073551),
        "php":         ("brew-php", 0x777BB4),  // CC-BY-SA-4.0
        "ruby":        ("brew-ruby", 0xCC342D),  // CC-BY-SA-2.5
        "starship":    ("brew-starship", 0xDD0B78),
        "htop":        ("brew-htop", 0x009020),
        "mysql":       ("brew-mysql", 0x4479A1),
        "qemu":        ("brew-qemu", 0xFF6600),
        "vim":         ("brew-vim", 0x019733),
        "ansible":     ("brew-ansible", 0xEE0000),
        "podman":      ("brew-podman", 0x892CA0),
        "bat":         ("brew-bat", 0x31369E),
        "postgresql":  ("brew-postgresql", 0x4169E1),
        "rclone":      ("brew-rclone", 0x3F79AD),
        "gradle":      ("brew-gradle", 0x02303A),
        "zsh":         ("brew-zsh", 0xF15A24),
        "deno":        ("brew-deno", 0x000000),  // MIT
        "tailscale":   ("brew-tailscale", 0x242424),
        "hugo":        ("brew-hugo", 0xFF4088),
        "composer":    ("brew-composer", 0x885630),
        "fastlane":    ("brew-fastlane", 0x00F200),
        "sqlite":      ("brew-sqlite", 0x003B57),
        "trivy":       ("brew-trivy", 0x1904DA),
        "ruff":        ("brew-ruff", 0xD7FF64),
        "pre-commit":  ("brew-precommit", 0xFAB040),
        "nginx":       ("brew-nginx", 0x009639),
        "lua":         ("brew-lua", 0x000080),
        "poetry":      ("brew-poetry", 0x60A5FA),
        "mpv":         ("brew-mpv", 0x691F69),
        "numpy":       ("brew-numpy", 0x013243),
        "opentofu":    ("brew-opentofu", 0xFFDA18),
        "dotnet":      ("brew-dotnet", 0x512BD4),
        "yarn":        ("brew-yarn", 0x2C8EBB),  // CC-BY-4.0
        "caddy":       ("brew-caddy", 0x1F88C0),
        "opencv":      ("brew-opencv", 0x5C3EE8),
        "zig":         ("brew-zig", 0xF7A41D),  // CC-BY-SA-4.0
        "qt":          ("brew-qt", 0x41CD52),
        "httpie":      ("brew-httpie", 0x73DC8C),
        "k6":          ("brew-k6", 0x7D64FF),
        "railway":     ("brew-railway", 0x0B0D0E),
        "gdal":        ("brew-gdal", 0x5CAE58),
        "subversion":  ("brew-subversion", 0x809CC9),
        "duckdb":      ("brew-duckdb", 0xFFF000),
        "temporal":    ("brew-temporal", 0x000000),
        "wireshark":   ("brew-wireshark", 0x1679A7),
        "supabase":    ("brew-supabase", 0x3FCF8E),
        "nushell":     ("brew-nushell", 0x4E9A06),
        "openvpn":     ("brew-openvpn", 0xEA7E20),
        "gstreamer":   ("brew-gstreamer", 0xFF3131),
        "syncthing":   ("brew-syncthing", 0x0891D1),
        "biome":       ("brew-biome", 0x60A5FA),
        "gh":          ("brew-github", 0x181717),
        "bun":         ("cli-bun", 0x000000),
    ]

    /// The brand colour, adjusted so it reads on both appearances: a near-black
    /// or grey brand follows the label colour, a very dark one is lifted in
    /// dark mode, and a very light one (DuckDB's yellow) deepened in light mode.
    var tint: Color {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        let brand = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let saturation = brand.saturationComponent
        if luminance < 0.2 && saturation < 0.35 { return Color(nsColor: .labelColor) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return luminance < 0.25 ? brand.blended(withFraction: 0.45, of: .white) ?? brand : brand
            }
            return luminance > 0.6 ? brand.blended(withFraction: 0.4, of: .black) ?? brand : brand
        })
    }
}
