import CArchive
import CryptoKit
import Foundation
import Security

public enum PersonalSourceZIP {
    private typealias Failure = PersonalGitHubSource.Failure

    /// Expand regular files into a new private directory. Never ask the archive
    /// library to materialize paths, links, ACLs or special files itself.
    static func unpack(_ url: URL, into root: URL) throws -> URL {
        let invalid = Failure("This ZIP needs the vendor’s installation instructions. Open the release page.", .releasePage)
        guard let reader = archive_read_new() else { throw invalid }
        defer { archive_read_free(reader) }
        guard archive_read_support_format_zip(reader) == 0, archive_read_open_filename(reader, url.path, 65536) == 0 else { throw invalid }
        var entry: OpaquePointer?
        var seen = Set<String>()
        var roots = Set<String>()
        var files = [String]()
        var metadataPartners = Set<String>()
        var links = [(destination: URL, target: String)]()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try Task.checkCancellation()
            let status = archive_read_next_header(reader, &entry)
            if status == 1 { break }
            guard status == 0, let entry, let path = archive_entry_pathname(entry), let name = String(validatingCString: path),
                  archive_entry_is_encrypted(entry) == 0, archive_entry_hardlink(entry) == nil else { throw invalid }
            let kind = Int32(archive_entry_filetype(entry))
            let directory = kind == S_IFDIR
            let relative = directory && name.hasSuffix("/") ? String(name.dropLast()) : name
            guard relative.utf8.count < Int(PATH_MAX) else { throw invalid }
            let parts = relative.components(separatedBy: "/")
            guard directory || kind == S_IFREG || kind == S_IFLNK, parts.count <= 40, seen.count < 30000,
                  !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains(":") || $0.contains("\\") }),
                  seen.insert(relative.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw invalid }
            if let index = parts.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) {
                guard index <= 3 else { throw invalid }
                roots.insert(parts[...index].joined(separator: "/"))
            } else if !directory { throw invalid }
            if let leaf = parts.last, leaf.hasPrefix("._") {
                guard kind == S_IFREG, leaf.count > 2 else { throw invalid }
                var metadata = Data()
                while true {
                    let count = archive_read_data(reader, &buffer, buffer.count)
                    guard count >= 0, metadata.count + count <= 65536 else { throw invalid }
                    if count == 0 { break }
                    metadata.append(contentsOf: buffer.prefix(count))
                }
                guard isMetadataSidecar(metadata) else { throw invalid }
                let partner = (parts.dropLast() + [String(leaf.dropFirst(2))]).joined(separator: "/")
                metadataPartners.insert(partner)
                total += metadata.count
                guard total <= 1_073_741_824 else { throw invalid }
                continue
            }
            files.append(relative)
            let dest = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: directory ? dest : dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if directory { continue }
            if kind == S_IFLNK {
                guard let target = archive_entry_symlink(entry), let value = String(validatingCString: target),
                      !value.isEmpty, !value.hasPrefix("/"), value.utf8.count < 1024,
                      // Conservative for the initial ZIP route. Framework links such as
                      // Versions/Current/Foo need no parent traversal.
                      !value.components(separatedBy: "/").contains("..") else { throw invalid }
                links.append((dest, value))
                continue
            }
            let fd = open(dest.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw invalid }
            let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? output.close() }
            // Finder preserves these modes when the user moves the app. The
            // staging parent is private, but the installed app can be shared.
            let installedMode: mode_t = archive_entry_perm(entry) & 0o111 == 0 ? 0o644 : 0o755
            guard fchmod(fd, installedMode) == 0 else { throw invalid }
            while true {
                let count = archive_read_data(reader, &buffer, buffer.count)
                guard count >= 0, total + count <= 1_073_741_824 else { throw invalid }
                if count == 0 { break }
                total += count
                try output.write(contentsOf: Data(buffer.prefix(count)))
            }
        }
        guard metadataPartners.isSubset(of: Set(files)), roots.count == 1, let app = roots.first,
              files.allSatisfy({ $0 == app || $0.hasPrefix(app + "/") || app.hasPrefix($0 + "/") }) else { throw invalid }
        let application = root.appendingPathComponent(app)
        // Create links only after the last file write. A link masquerading as
        // an archive directory collides with that directory and fails here.
        for link in links {
            try FileManager.default.createSymbolicLink(atPath: link.destination.path, withDestinationPath: link.target)
        }
        guard let resolvedApp = realpath(application.path, nil) else { throw invalid }
        defer { free(resolvedApp) }
        let prefix = String(cString: resolvedApp) + "/"
        for link in links {
            guard let resolved = realpath(link.destination.path, nil) else { throw invalid }
            defer { free(resolved) }
            guard String(cString: resolved).hasPrefix(prefix) else { throw invalid }
        }
        return application
    }

    /// ditto packs filesystem metadata beside the actual entry in some ZIPs.
    /// Do not materialize these as signed resources, restore untrusted xattrs,
    /// or drop a payload-bearing resource fork. The companion must also exist.
    private static func isMetadataSidecar(_ bytes: Data) -> Bool {
        func number(_ start: Int, _ count: Int) -> Int {
            bytes[start..<(start + count)].reduce(0) { ($0 << 8) | Int($1) }
        }
        guard bytes.count >= 26, number(0, 4) == 0x00051607, number(4, 4) == 0x00020000 else { return false }
        let count = number(24, 2)
        let headersEnd = 26 + count * 12
        guard (1...2).contains(count), headersEnd <= bytes.count else { return false }
        var ids = Set<Int>()
        for i in 0..<count {
            let entry = 26 + i * 12
            let id = number(entry, 4), offset = number(entry + 4, 4), length = number(entry + 8, 4)
            guard ids.insert(id).inserted, offset >= headersEnd, offset + length <= bytes.count else { return false }
            switch id {
            case 2: guard length == 0 else { return false }
            case 9:
                // Empty FinderInfo, optionally followed by the macOS extended
                // attributes section. Neither is a standalone file to extract.
                guard length >= 32, bytes[offset..<(offset + 32)].allSatisfy({ $0 == 0 }) else { return false }
                if length > 32 {
                    let attributes = (offset + 32 + 3) & ~3
                    guard attributes + 4 <= offset + length, number(attributes, 4) == 0x41545452 else { return false }
                }
            default: return false
            }
        }
        return ids.contains(9)
    }

    public struct Identity: Codable, Equatable, Sendable {
        public let bundle: String
        public let version: String
        public let build: String
        public let team: String?
        public let code: Data?
        public let device: UInt64
        public let inode: UInt64

        public init(at url: URL) throws {
            var stat = Darwin.stat()
            guard lstat(url.path, &stat) == 0, (stat.st_mode & S_IFMT) == S_IFDIR,
                  let data = try? Data(contentsOf: BundleLayout.infoPlistURL(for: url)),
                  let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty else { throw Failure("Cannot read the installed application identity.") }
            self.bundle = bundle
            version = info["CFBundleShortVersionString"] as? String ?? ""
            build = info["CFBundleVersion"] as? String ?? ""
            device = UInt64(UInt32(bitPattern: stat.st_dev))
            inode = UInt64(stat.st_ino)
            var staticCode: SecStaticCode?
            var signing: CFDictionary?
            if SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode {
                SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signing)
            }
            let dict = signing as? [String: Any]
            team = dict?[kSecCodeInfoTeamIdentifier as String] as? String
            code = dict?[kSecCodeInfoUnique as String] as? Data
        }
    }

    public static func inspect(app: URL, installed: URL, anchor: Identity, tag: String) async throws -> Identity {
        let candidate = try await offCooperativePool {
            try inspectBundle(app: app, installed: installed, anchor: anchor, tag: tag)
        }
        try await SignatureVerifier.verifyInstallArtifact(downloadedApp: app, installedApp: installed, canRunIntel: false)
        let policy = try await ChildProcess.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", app.path], onCancel: .terminateChild)
        guard policy.succeeded else { throw Failure("macOS did not approve this Developer ID application.", .blocked) }
        return candidate
    }

    private static func inspectBundle(app: URL, installed: URL, anchor: Identity, tag: String) throws -> Identity {
        guard try Identity(at: installed) == anchor else { throw Failure("The installed copy changed. Review the source again.", .reviewSource) }
        let candidate = try Identity(at: app)
        guard let team = anchor.team, candidate.team != nil, candidate.code != nil else {
            throw Failure("No verified Developer ID identity. Use the release page.", .releasePage)
        }
        guard candidate.team == team, candidate.bundle == anchor.bundle else {
            throw Failure("The package publisher or bundle identifier does not match this installation.", .blocked)
        }
        guard let local = PersonalGitHubSource.Version(anchor.version),
              let offered = PersonalGitHubSource.Version(tag),
              let packaged = PersonalGitHubSource.Version(candidate.version) else {
            throw Failure("The package version cannot be reliably compared. Use the release page.", .releasePage)
        }
        guard offered > local, packaged == offered,
              anchor.build.isEmpty || candidate.build.isEmpty || VersionComparator.compare(candidate.build, anchor.build) != .orderedAscending else {
            throw Failure("Package identity or version does not match this installation.", .blocked)
        }
        try SignatureVerifier.verifyCodeSignature(appAt: installed)
        let oldInfo = SignatureVerifier.infoPlist(of: installed)
        let newInfo = SignatureVerifier.infoPlist(of: app)
        guard ["CFBundleExecutable", "CFBundleName", "CFBundleDisplayName"].allSatisfy({ key in
            (oldInfo[key] as? String) == (newInfo[key] as? String)
        }) else { throw Failure("The package edition does not match this installation.", .blocked) }
        guard let oldSignature = SignatureVerifier.signingSummary(at: installed),
              let newSignature = SignatureVerifier.signingSummary(at: app),
              newSignature.authorities.first?.hasPrefix("Developer ID Application: ") == true else {
            throw Failure("No verified Developer ID identity. Use the release page.", .releasePage)
        }
        guard newSignature.entitlements == oldSignature.entitlements else {
            throw Failure("The app’s requested permissions changed. Use the vendor’s instructions.", .releasePage)
        }
        for copy in [app, installed] {
            let reasons = AutomaticUpdateSuggestion.classify(bundle: copy).reasons
            let contents = copy.appendingPathComponent("Contents")
            guard !reasons.contains(where: { [.networkExtension, .fileSync, .systemExtension, .inputMethod, .unreadableBundle].contains($0) }),
                  !["Library/LaunchServices", "Library/LaunchDaemons", "Library/SystemExtensions", "Library/LoginItems", "PlugIns"].contains(where: {
                      FileManager.default.fileExists(atPath: contents.appendingPathComponent($0).path)
                  }) else { throw Failure("This app needs its vendor’s installation procedure.", .releasePage) }
        }
        guard SignatureVerifier.executableArchitectures(ofAppAt: app).contains(NSBundleExecutableArchitectureARM64) else {
            throw Failure("The package does not contain a confirmed arm64 executable.")
        }
        return candidate
    }
}
