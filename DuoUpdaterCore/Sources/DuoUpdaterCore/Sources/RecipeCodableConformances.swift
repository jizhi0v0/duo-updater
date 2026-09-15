import Foundation

// JSON coding for the recipe types. The convention — shapes, strictness, how
// defaults are found — is stated once, on `RecipeCoding`. Read that first.
//
// Each decoder takes its defaults from a value built by the Swift initializer
// (`defaults` below), so an initializer default and a decoding default cannot
// disagree. The placeholders passed for required parameters are overwritten.

private let placeholderURL = URL(fileURLWithPath: "/")

// MARK: - VendorProbeRecipe

extension VendorProbeRecipe: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleID, channel, variant, hostRequirement, installedVersionPattern
        case buildLineage, url, identities, track, mode, versionPattern
        case transientBodyPattern, trackClosedPattern, downloadURL, changelogURL
        case selectHighest, versionIsBuild, buildNamespace, displayVersionPattern
        case publishedAtPattern, minimumSystemVersionPattern, maximumSystemVersionPattern
        case entryStartPattern, install, requestBody
        case followRedirects, requestHeaders
    }

    private static var codingDefaults: VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "", url: placeholderURL, mode: .responseBody, versionPattern: "")
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        self.init(
            bundleID: try c.decode(String.self, forKey: .bundleID),
            url: try c.decode(URL.self, forKey: .url),
            mode: try c.decode(Mode.self, forKey: .mode),
            versionPattern: try c.decode(String.self, forKey: .versionPattern),
            transientBodyPattern: try c.decodeOptional(
                String.self, forKey: .transientBodyPattern, default: d.transientBodyPattern),
            trackClosedPattern: try c.decodeOptional(
                String.self, forKey: .trackClosedPattern, default: d.trackClosedPattern),
            downloadURL: try c.decodeOptional(URL.self, forKey: .downloadURL, default: d.downloadURL),
            changelogURL: try c.decodeOptional(
                URL.self, forKey: .changelogURL, default: d.changelogURL),
            selectHighest: try c.decode(Bool.self, forKey: .selectHighest, default: d.selectHighest),
            versionIsBuild: try c.decode(
                Bool.self, forKey: .versionIsBuild, default: d.versionIsBuild),
            buildNamespace: try c.decode(
                InstalledApp.BuildNamespace.self, forKey: .buildNamespace, default: d.buildNamespace),
            displayVersionPattern: try c.decodeOptional(
                String.self, forKey: .displayVersionPattern, default: d.displayVersionPattern),
            publishedAtPattern: try c.decodeOptional(
                String.self, forKey: .publishedAtPattern, default: d.publishedAtPattern),
            minimumSystemVersionPattern: try c.decodeOptional(
                String.self, forKey: .minimumSystemVersionPattern,
                default: d.minimumSystemVersionPattern),
            maximumSystemVersionPattern: try c.decodeOptional(
                String.self, forKey: .maximumSystemVersionPattern,
                default: d.maximumSystemVersionPattern),
            entryStartPattern: try c.decodeOptional(
                String.self, forKey: .entryStartPattern, default: d.entryStartPattern),
            install: try c.decodeOptional(VendorInstallSpec.self, forKey: .install, default: d.install),
            requestBody: try c.decodeOptional(
                RequestBody.self, forKey: .requestBody, default: d.requestBody),
            requestHeaders: try c.decode(
                [String: String].self, forKey: .requestHeaders, default: d.requestHeaders),
            followRedirects: try c.decode(
                Bool.self, forKey: .followRedirects, default: d.followRedirects),
            channel: try c.decode(ReleaseChannel.self, forKey: .channel, default: d.channel),
            identities: try c.decode(
                [ProbeIdentity].self, forKey: .identities, default: d.identities),
            track: try c.decodeOptional(RolloutTrack.self, forKey: .track, default: d.track),
            variant: try c.decodeOptional(String.self, forKey: .variant, default: d.variant),
            hostRequirement: try c.decodeOptional(
                VendorHostRequirement.self, forKey: .hostRequirement, default: d.hostRequirement),
            installedVersionPattern: try c.decodeOptional(
                String.self, forKey: .installedVersionPattern, default: d.installedVersionPattern),
            buildLineage: try c.decodeOptional(
                BuildLineageSpec.self, forKey: .buildLineage, default: d.buildLineage))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(channel, forKey: .channel)
        try c.encodeOptional(variant, forKey: .variant, defaultIsNil: d.variant == nil)
        try c.encodeOptional(
            hostRequirement, forKey: .hostRequirement, defaultIsNil: d.hostRequirement == nil)
        try c.encodeOptional(
            installedVersionPattern, forKey: .installedVersionPattern,
            defaultIsNil: d.installedVersionPattern == nil)
        try c.encodeOptional(buildLineage, forKey: .buildLineage, defaultIsNil: d.buildLineage == nil)
        try c.encode(url, forKey: .url)
        try c.encode(identities, forKey: .identities)
        try c.encodeOptional(track, forKey: .track, defaultIsNil: d.track == nil)
        try c.encode(mode, forKey: .mode)
        try c.encode(versionPattern, forKey: .versionPattern)
        try c.encodeOptional(
            transientBodyPattern, forKey: .transientBodyPattern,
            defaultIsNil: d.transientBodyPattern == nil)
        try c.encodeOptional(
            trackClosedPattern, forKey: .trackClosedPattern, defaultIsNil: d.trackClosedPattern == nil)
        try c.encodeOptional(downloadURL, forKey: .downloadURL, defaultIsNil: d.downloadURL == nil)
        try c.encodeOptional(changelogURL, forKey: .changelogURL, defaultIsNil: d.changelogURL == nil)
        try c.encode(selectHighest, forKey: .selectHighest)
        try c.encode(versionIsBuild, forKey: .versionIsBuild)
        try c.encode(buildNamespace, forKey: .buildNamespace)
        try c.encodeOptional(
            displayVersionPattern, forKey: .displayVersionPattern,
            defaultIsNil: d.displayVersionPattern == nil)
        try c.encodeOptional(
            publishedAtPattern, forKey: .publishedAtPattern, defaultIsNil: d.publishedAtPattern == nil)
        try c.encodeOptional(
            minimumSystemVersionPattern, forKey: .minimumSystemVersionPattern,
            defaultIsNil: d.minimumSystemVersionPattern == nil)
        try c.encodeOptional(
            maximumSystemVersionPattern, forKey: .maximumSystemVersionPattern,
            defaultIsNil: d.maximumSystemVersionPattern == nil)
        try c.encodeOptional(
            entryStartPattern, forKey: .entryStartPattern, defaultIsNil: d.entryStartPattern == nil)
        try c.encodeOptional(install, forKey: .install, defaultIsNil: d.install == nil)
        try c.encodeOptional(requestBody, forKey: .requestBody, defaultIsNil: d.requestBody == nil)
        try c.encode(followRedirects, forKey: .followRedirects)
        try c.encode(requestHeaders, forKey: .requestHeaders)
    }
}

extension VendorProbeRecipe.Mode: Codable {
    enum CodingKind: String, CaseIterable {
        case redirectFilename, responseBody, zipEntryPlist
    }

    public init(from decoder: Decoder) throws {
        let (kind, c) = try RecipeCoding.taggedObject(CodingKind.self, in: decoder) {
            switch $0 {
            case .redirectFilename, .responseBody: return []
            case .zipEntryPlist: return ["entry", "key"]
            }
        }
        switch kind {
        case .redirectFilename: self = .redirectFilename
        case .responseBody: self = .responseBody
        case .zipEntryPlist:
            self = .zipEntryPlist(
                entry: try c.decode(String.self, forKey: .init("entry")),
                key: try c.decode(String.self, forKey: .init("key")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RecipeCoding.AnyKey.self)
        switch self {
        case .redirectFilename:
            try c.encode(CodingKind.redirectFilename.rawValue, forKey: .init("kind"))
        case .responseBody:
            try c.encode(CodingKind.responseBody.rawValue, forKey: .init("kind"))
        case .zipEntryPlist(let entry, let key):
            try c.encode(CodingKind.zipEntryPlist.rawValue, forKey: .init("kind"))
            try c.encode(entry, forKey: .init("entry"))
            try c.encode(key, forKey: .init("key"))
        }
    }
}

extension VendorProbeRecipe.BuildLineageSpec: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable { case url, entryPattern }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            url: try c.decode(URL.self, forKey: .url),
            entryPattern: try c.decode(String.self, forKey: .entryPattern))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encode(entryPattern, forKey: .entryPattern)
    }
}

extension VendorProbeRecipe.RequestBody: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable { case contentType, json }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let json = try c.decode(String.self, forKey: .json)
        let d = Self(json: "")
        self.init(
            contentType: try c.decode(String.self, forKey: .contentType, default: d.contentType),
            json: json)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(json, forKey: .json)
    }
}

// MARK: - VendorInstallSpec

extension VendorInstallSpec: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case urlSource, kind, checksumPattern, requestHeaders, nestedArchivePath
    }

    private static var codingDefaults: VendorInstallSpec {
        VendorInstallSpec(urlSource: .fixed(placeholderURL), kind: .zip)
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        self.init(
            urlSource: try c.decode(URLSource.self, forKey: .urlSource),
            kind: try c.decode(VendorInstallerKind.self, forKey: .kind),
            checksumPattern: try c.decodeOptional(
                String.self, forKey: .checksumPattern, default: d.checksumPattern),
            requestHeaders: try c.decode(
                [String: String].self, forKey: .requestHeaders, default: d.requestHeaders),
            nestedArchivePath: try c.decodeOptional(
                String.self, forKey: .nestedArchivePath, default: d.nestedArchivePath))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        try c.encode(urlSource, forKey: .urlSource)
        try c.encode(kind, forKey: .kind)
        try c.encodeOptional(
            checksumPattern, forKey: .checksumPattern, defaultIsNil: d.checksumPattern == nil)
        try c.encode(requestHeaders, forKey: .requestHeaders)
        try c.encodeOptional(
            nestedArchivePath, forKey: .nestedArchivePath, defaultIsNil: d.nestedArchivePath == nil)
    }
}

extension VendorInstallSpec.URLSource: Codable {
    enum CodingKind: String, CaseIterable {
        case bodyPattern, bodyPatternLast, bodyPatternHighestVersioned, bodyPatternRelative
        case bodyTemplate, versionTemplate, redirect, fixed
    }

    public init(from decoder: Decoder) throws {
        let (kind, c) = try RecipeCoding.taggedObject(CodingKind.self, in: decoder) {
            switch $0 {
            case .bodyPattern, .bodyPatternLast, .bodyPatternHighestVersioned: return ["pattern"]
            case .bodyPatternRelative: return ["pattern", "base"]
            case .bodyTemplate: return ["template", "fields"]
            case .versionTemplate: return ["template"]
            case .redirect, .fixed: return ["url"]
            }
        }
        switch kind {
        case .bodyPattern:
            self = .bodyPattern(try c.decode(String.self, forKey: .init("pattern")))
        case .bodyPatternLast:
            self = .bodyPatternLast(try c.decode(String.self, forKey: .init("pattern")))
        case .bodyPatternHighestVersioned:
            self = .bodyPatternHighestVersioned(try c.decode(String.self, forKey: .init("pattern")))
        case .bodyPatternRelative:
            self = .bodyPatternRelative(
                try c.decode(String.self, forKey: .init("pattern")),
                base: try c.decode(URL.self, forKey: .init("base")))
        case .bodyTemplate:
            self = .bodyTemplate(
                try c.decode(String.self, forKey: .init("template")),
                fields: try c.decode([String].self, forKey: .init("fields")))
        case .versionTemplate:
            self = .versionTemplate(try c.decode(String.self, forKey: .init("template")))
        case .redirect:
            self = .redirect(try c.decode(URL.self, forKey: .init("url")))
        case .fixed:
            self = .fixed(try c.decode(URL.self, forKey: .init("url")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RecipeCoding.AnyKey.self)
        let kind: CodingKind
        switch self {
        case .bodyPattern(let pattern):
            kind = .bodyPattern
            try c.encode(pattern, forKey: .init("pattern"))
        case .bodyPatternLast(let pattern):
            kind = .bodyPatternLast
            try c.encode(pattern, forKey: .init("pattern"))
        case .bodyPatternHighestVersioned(let pattern):
            kind = .bodyPatternHighestVersioned
            try c.encode(pattern, forKey: .init("pattern"))
        case .bodyPatternRelative(let pattern, let base):
            kind = .bodyPatternRelative
            try c.encode(pattern, forKey: .init("pattern"))
            try c.encode(base, forKey: .init("base"))
        case .bodyTemplate(let template, let fields):
            kind = .bodyTemplate
            try c.encode(template, forKey: .init("template"))
            try c.encode(fields, forKey: .init("fields"))
        case .versionTemplate(let template):
            kind = .versionTemplate
            try c.encode(template, forKey: .init("template"))
        case .redirect(let url):
            kind = .redirect
            try c.encode(url, forKey: .init("url"))
        case .fixed(let url):
            kind = .fixed
            try c.encode(url, forKey: .init("url"))
        }
        try c.encode(kind.rawValue, forKey: .init("kind"))
    }
}

extension VendorInstallerKind: Codable {
    var codingName: String {
        switch self {
        case .zip: return "zip"
        case .dmg: return "dmg"
        case .tarGz: return "tarGz"
        case .pkg: return "pkg"
        }
    }

    public init(from decoder: Decoder) throws {
        self = try decodeCaseName(Self.allCases, name: \.codingName, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try codingName.encode(to: encoder)
    }
}

extension VendorHostRequirement: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable { case minimumSystemVersion, architectures }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        self.init(
            minimumSystemVersion: try c.decodeOptional(
                String.self, forKey: .minimumSystemVersion, default: d.minimumSystemVersion),
            architectures: try c.decode(
                [HostArch].self, forKey: .architectures, default: d.architectures))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeOptional(
            minimumSystemVersion, forKey: .minimumSystemVersion,
            defaultIsNil: Self().minimumSystemVersion == nil)
        try c.encode(architectures, forKey: .architectures)
    }
}

extension HostArch: Codable {
    var codingName: String {
        switch self {
        case .arm64: return "arm64"
        case .x86_64: return "x86_64"
        }
    }

    public init(from decoder: Decoder) throws {
        self = try decodeCaseName(Self.allCases, name: \.codingName, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try codingName.encode(to: encoder)
    }
}

/// A payloadless enum written as its case name, refusing any other string.
private func decodeCaseName<T>(
    _ cases: [T], name: (T) -> String, from decoder: Decoder
) throws -> T {
    let text = try String(from: decoder)
    guard let match = cases.first(where: { name($0) == text }) else {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "unknown value `\(text)`; expected one of: "
                + cases.map(name).joined(separator: ", ")))
    }
    return match
}

// MARK: - ProbeIdentity, RolloutTrack

extension ProbeIdentity: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case location, encoding, validationPattern, placeholder, fallback, maxBytes
    }

    private static var codingDefaults: ProbeIdentity {
        ProbeIdentity(location: .home(""), encoding: .plain, validationPattern: "")
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        self.init(
            location: try c.decode(Location.self, forKey: .location),
            encoding: try c.decode(Encoding.self, forKey: .encoding),
            validationPattern: try c.decode(String.self, forKey: .validationPattern),
            placeholder: try c.decode(String.self, forKey: .placeholder, default: d.placeholder),
            fallback: try c.decodeOptional(String.self, forKey: .fallback, default: d.fallback),
            maxBytes: try c.decode(Int.self, forKey: .maxBytes, default: d.maxBytes))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(location, forKey: .location)
        try c.encode(encoding, forKey: .encoding)
        try c.encode(validationPattern, forKey: .validationPattern)
        try c.encode(placeholder, forKey: .placeholder)
        try c.encodeOptional(
            fallback, forKey: .fallback, defaultIsNil: Self.codingDefaults.fallback == nil)
        try c.encode(maxBytes, forKey: .maxBytes)
    }
}

extension ProbeIdentity.Encoding: Codable {
    enum CodingKind: String, CaseIterable { case plain, base64, jsonKey, jwtClaim }

    public init(from decoder: Decoder) throws {
        let (kind, c) = try RecipeCoding.taggedObject(CodingKind.self, in: decoder) {
            switch $0 {
            case .plain, .base64: return []
            case .jsonKey: return ["key"]
            case .jwtClaim: return ["tokenPath", "claimPath"]
            }
        }
        switch kind {
        case .plain: self = .plain
        case .base64: self = .base64
        case .jsonKey: self = .jsonKey(try c.decode(String.self, forKey: .init("key")))
        case .jwtClaim:
            self = .jwtClaim(
                tokenPath: try c.decode([String].self, forKey: .init("tokenPath")),
                claimPath: try c.decode([String].self, forKey: .init("claimPath")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RecipeCoding.AnyKey.self)
        switch self {
        case .plain:
            try c.encode(CodingKind.plain.rawValue, forKey: .init("kind"))
        case .base64:
            try c.encode(CodingKind.base64.rawValue, forKey: .init("kind"))
        case .jsonKey(let key):
            try c.encode(CodingKind.jsonKey.rawValue, forKey: .init("kind"))
            try c.encode(key, forKey: .init("key"))
        case .jwtClaim(let tokenPath, let claimPath):
            try c.encode(CodingKind.jwtClaim.rawValue, forKey: .init("kind"))
            try c.encode(tokenPath, forKey: .init("tokenPath"))
            try c.encode(claimPath, forKey: .init("claimPath"))
        }
    }
}

extension ProbeIdentity.Location: Codable {
    enum CodingKind: String, CaseIterable { case applicationSupport, home }

    public init(from decoder: Decoder) throws {
        let (kind, c) = try RecipeCoding.taggedObject(CodingKind.self, in: decoder) { _ in ["path"] }
        let path = try c.decode(String.self, forKey: .init("path"))
        switch kind {
        case .applicationSupport: self = .applicationSupport(path)
        case .home: self = .home(path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RecipeCoding.AnyKey.self)
        switch self {
        case .applicationSupport(let path):
            try c.encode(CodingKind.applicationSupport.rawValue, forKey: .init("kind"))
            try c.encode(path, forKey: .init("path"))
        case .home(let path):
            try c.encode(CodingKind.home.rawValue, forKey: .init("kind"))
            try c.encode(path, forKey: .init("path"))
        }
    }
}

extension RolloutTrack: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case selector, contrastValue, contrastTrackName
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selector: try c.decode(ProbeIdentity.self, forKey: .selector),
            contrastValue: try c.decode(String.self, forKey: .contrastValue),
            contrastTrackName: try c.decode(String.self, forKey: .contrastTrackName))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selector, forKey: .selector)
        try c.encode(contrastValue, forKey: .contrastValue)
        try c.encode(contrastTrackName, forKey: .contrastTrackName)
    }
}

// MARK: - GitHubReleaseRule

extension GitHubCandidateScope: Codable {}

extension GitHubReleaseRule: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleID, owner, repo, usePrereleases, listPageSize, versionPattern
        case candidateScope, probesNewestFirst, installedTagPrefix, channel
        case installAssetPattern, installerKind
    }

    private static var codingDefaults: GitHubReleaseRule {
        GitHubReleaseRule(bundleID: "", owner: "", repo: "")
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        self.init(
            bundleID: try c.decode(String.self, forKey: .bundleID),
            owner: try c.decode(String.self, forKey: .owner),
            repo: try c.decode(String.self, forKey: .repo),
            usePrereleases: try c.decode(
                Bool.self, forKey: .usePrereleases, default: d.usePrereleases),
            listPageSize: try c.decode(Int.self, forKey: .listPageSize, default: d.listPageSize),
            versionPattern: try c.decode(
                String.self, forKey: .versionPattern, default: d.versionPattern),
            candidateScope: try c.decode(
                GitHubCandidateScope.self, forKey: .candidateScope, default: d.candidateScope),
            installedTagPrefix: try c.decodeOptional(
                String.self, forKey: .installedTagPrefix, default: d.installedTagPrefix),
            installAssetPattern: try c.decodeOptional(
                String.self, forKey: .installAssetPattern, default: d.installAssetPattern),
            installerKind: try c.decodeOptional(
                VendorInstallerKind.self, forKey: .installerKind, default: d.installerKind),
            channel: try c.decode(ReleaseChannel.self, forKey: .channel, default: d.channel),
            probesNewestFirst: try c.decode(
                Bool.self, forKey: .probesNewestFirst, default: d.probesNewestFirst))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let d = Self.codingDefaults
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(owner, forKey: .owner)
        try c.encode(repo, forKey: .repo)
        try c.encode(usePrereleases, forKey: .usePrereleases)
        try c.encode(listPageSize, forKey: .listPageSize)
        try c.encode(versionPattern, forKey: .versionPattern)
        try c.encode(candidateScope, forKey: .candidateScope)
        try c.encode(probesNewestFirst, forKey: .probesNewestFirst)
        try c.encodeOptional(
            installedTagPrefix, forKey: .installedTagPrefix, defaultIsNil: d.installedTagPrefix == nil)
        try c.encode(channel, forKey: .channel)
        try c.encodeOptional(
            installAssetPattern, forKey: .installAssetPattern,
            defaultIsNil: d.installAssetPattern == nil)
        try c.encodeOptional(installerKind, forKey: .installerKind, defaultIsNil: d.installerKind == nil)
    }
}

// MARK: - MacAppStoreProbeCase

extension MacAppStoreProbeCase.Route: Codable {}

extension MacAppStoreProbeCase: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleID, trackId, region, expectedKind, route
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self(bundleID: "", trackId: 0, expectedKind: "", route: .nativeMac)
        self.init(
            bundleID: try c.decode(String.self, forKey: .bundleID),
            trackId: try c.decode(Int.self, forKey: .trackId),
            region: try c.decode(String.self, forKey: .region, default: d.region),
            expectedKind: try c.decode(String.self, forKey: .expectedKind),
            route: try c.decode(Route.self, forKey: .route))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(trackId, forKey: .trackId)
        try c.encode(region, forKey: .region)
        try c.encode(expectedKind, forKey: .expectedKind)
        try c.encode(route, forKey: .route)
    }
}

// MARK: - Channel proofs

extension ChannelProofKey: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable { case bundleID, channel }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try c.decode(String.self, forKey: .bundleID),
            try c.decode(ReleaseChannel.self, forKey: .channel))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(channel, forKey: .channel)
    }
}

extension ChannelArtifactProof: Codable {
    enum CodingKind: String, CaseIterable { case artifact, recipeAnchor }

    public init(from decoder: Decoder) throws {
        let (kind, c) = try RecipeCoding.taggedObject(CodingKind.self, in: decoder) {
            switch $0 {
            case .artifact: return ["pattern"]
            case .recipeAnchor: return ["pattern", "fields"]
            }
        }
        let pattern = try c.decode(String.self, forKey: .init("pattern"))
        switch kind {
        case .artifact:
            self = .artifact(pattern)
        case .recipeAnchor:
            let key = RecipeCoding.AnyKey("fields")
            let fields = try c.decode([String].self, forKey: key)
            guard Set(fields).count == fields.count else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath + [key],
                    debugDescription: "`fields` names a field more than once"))
            }
            self = .recipeAnchor(pattern, in: Set(fields))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RecipeCoding.AnyKey.self)
        switch self {
        case .artifact(let pattern):
            try c.encode(CodingKind.artifact.rawValue, forKey: .init("kind"))
            try c.encode(pattern, forKey: .init("pattern"))
        case .recipeAnchor(let pattern, let fields):
            try c.encode(CodingKind.recipeAnchor.rawValue, forKey: .init("kind"))
            try c.encode(pattern, forKey: .init("pattern"))
            // Sorted: a `Set` has no order, and the file should not churn.
            try c.encode(fields.sorted(), forKey: .init("fields"))
        }
    }
}

/// A `[ChannelProofKey: ChannelArtifactProof]` table in its JSON form — an array
/// of `{"bundleID", "channel", "proof"}` entries. See `RecipeCoding`.
///
/// A key listed twice is a decoding error, the way a duplicate key in the Swift
/// dictionary literal these tables were written as traps.
struct ChannelProofTable: Codable {
    var proofs: [ChannelProofKey: ChannelArtifactProof]

    init(_ proofs: [ChannelProofKey: ChannelArtifactProof]) {
        self.proofs = proofs
    }

    private enum EntryKeys: String, CodingKey, CaseIterable { case bundleID, channel, proof }

    private struct Entry: Codable {
        let key: ChannelProofKey
        let proof: ChannelArtifactProof

        init(key: ChannelProofKey, proof: ChannelArtifactProof) {
            self.key = key
            self.proof = proof
        }

        init(from decoder: Decoder) throws {
            try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: EntryKeys.self)
            let c = try decoder.container(keyedBy: EntryKeys.self)
            key = ChannelProofKey(
                try c.decode(String.self, forKey: .bundleID),
                try c.decode(ReleaseChannel.self, forKey: .channel))
            proof = try c.decode(ChannelArtifactProof.self, forKey: .proof)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: EntryKeys.self)
            try c.encode(key.bundleID, forKey: .bundleID)
            try c.encode(key.channel, forKey: .channel)
            try c.encode(proof, forKey: .proof)
        }
    }

    init(from decoder: Decoder) throws {
        var array = try decoder.unkeyedContainer()
        var proofs: [ChannelProofKey: ChannelArtifactProof] = [:]
        while !array.isAtEnd {
            let path = array.codingPath + [RecipeCoding.AnyKey("\(array.currentIndex)")]
            let entry = try array.decode(Entry.self)
            guard proofs[entry.key] == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: path, debugDescription: "\(entry.key) is listed more than once"))
            }
            proofs[entry.key] = entry.proof
        }
        self.proofs = proofs
    }

    func encode(to encoder: Encoder) throws {
        var array = encoder.unkeyedContainer()
        let ordered = proofs.sorted {
            ($0.key.bundleID, $0.key.channel.rawValue) < ($1.key.bundleID, $1.key.channel.rawValue)
        }
        for (key, proof) in ordered {
            try array.encode(Entry(key: key, proof: proof))
        }
    }
}

// MARK: - SparkleFeedCatalog

extension SparkleFeedCatalog.SupersededFeed: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable { case declared, live }

    init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            declared: try c.decode(URL.self, forKey: .declared),
            live: try c.decode(URL.self, forKey: .live))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(declared, forKey: .declared)
        try c.encode(live, forKey: .live)
    }
}
