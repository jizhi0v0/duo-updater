import Foundation
@testable import DuoUpdaterCore

/// A canonical, line-oriented text form of one `AppRecipeSet`, read by reflection
/// over stored properties. `RecipeGoldenTests` holds it to the committed goldens;
/// see that suite for why it exists.
///
/// One leaf per line, `path = value`:
///
///     probes = Array(count: 1)
///     probes[0] = struct VendorProbeRecipe
///     probes[0].bundleID = "com.example.App"
///     probes[0].variant = nil
///     probes[0].install? = struct VendorInstallSpec
///     probes[0].install?.urlSource = .bodyPatternRelative(_:base:)
///     probes[0].install?.urlSource.0 = "href=\"([^\"]+\\.dmg)\""
///     probes[0].install?.urlSource.base = URL("https://example.com/")
///     channelProofs[ChannelProofKey(bundleID: "com.example.App", channel: .beta)] = .artifact(_:)
///
/// - **Paths.** `.label` is a stored property; `[i]` an array element in declaration
///   order; `{i}` the i-th element of a `Set` after sorting; `[key]` a dictionary
///   entry, keyed by the key's one-line form and sorted by it; a trailing `?` is
///   one `Optional` layer that holds a value (so `x = nil` and `x? = ""` differ, and
///   `x?? = nil` is `.some(nil)`); `.0` / `.label` under an enum is its payload.
/// - **Values.** A `String` is quoted with `\\`, `\"`, `\n`, `\r`, `\t` escaped and
///   every other scalar outside printable ASCII written `\u{HEX}`, so the text is
///   pure ASCII and two strings that Swift's `==` calls canonically equivalent
///   (NFC/NFD) still dump differently. `Int` is bare, `Double` is `Double(…)`,
///   `Bool` is `true`/`false`, `URL` is `URL("absoluteString")`, `Data` is
///   `Data(base64: "…")`. A struct is `struct Name`, an enum `.case` or
///   `.case(label:_:)` followed by its payload lines, a collection its count.
/// - **Refusals.** Anything this does not know how to read faithfully throws
///   `Unrepresentable` naming the path and type, rather than producing a constant:
///   a value with no children that is not one of the leaf types above (another
///   integer width, `Float`, a class, a function), a `CustomReflectable` type other
///   than the standard library's own collections and `Optional` (its mirror is
///   whatever it chooses to show), and a payloadless enum with a custom
///   description (its case name cannot be read off `String(describing:)`).
///
/// `String(describing:)` is never used on a value that can nest a string: its
/// escaping of nested strings is inconsistent, and that has silently disabled a
/// check in this repository before.
enum RecipeGoldenDump {

    struct Unrepresentable: Error, CustomStringConvertible {
        let path: String
        let reason: String
        var description: String { "\(path.isEmpty ? "<root>" : path): \(reason)" }
    }

    /// One family's dump.
    struct Family: Sendable {
        let family: String
        /// `AppRecipeSet`'s stored property labels, `family` included, in order.
        let labels: [String]
        let text: String
    }

    /// The first lines of every golden. Part of the dump, so a golden is compared
    /// whole.
    static let preamble = [
        "// Generated from AppRecipeIndex.all by RecipeGoldenTests. Do not edit by hand.",
        "// Regenerate: \(RecipeGoldenCommand.record)",
    ]

    static func family(_ set: AppRecipeSet) throws -> Family {
        let mirror = try trustedMirror(of: set, at: "")
        var lines = preamble
        var labels: [String] = []
        for child in mirror.children {
            guard let label = child.label else {
                throw Unrepresentable(path: "", reason: "AppRecipeSet has an unlabelled stored property")
            }
            labels.append(label)
            lines.append("")
            render(try node(child.value, at: label), at: label, into: &lines)
        }
        return Family(family: set.family, labels: labels,
                      text: lines.joined(separator: "\n") + "\n")
    }

    // MARK: - The tree

    /// A value read by reflection, before it is laid out as lines.
    indirect enum Node {
        case leaf(String)
        case none
        case some(Node)
        case array([Node])
        /// Already sorted by each element's one-line form.
        case set([Node])
        /// Already sorted by each key's one-line form.
        case dictionary([(key: String, value: Node)])
        case structure(name: String, fields: [(label: String, value: Node)])
        /// `payload` is nil for a case without associated values; a label is nil
        /// for an unlabelled payload value.
        case enumCase(name: String, payload: [(label: String?, value: Node)]?)
    }

    static func node(_ value: Any, at path: String) throws -> Node {
        if let leaf = leaf(value) { return .leaf(leaf) }
        let type = typeName(of: value)
        let mirror = try trustedMirror(of: value, at: path)
        switch mirror.displayStyle {
        case .optional:
            guard let some = mirror.children.first else { return .none }
            return .some(try node(some.value, at: path + "?"))

        case .collection:
            return .array(try mirror.children.enumerated().map {
                try node($0.element.value, at: "\(path)[\($0.offset)]")
            })

        case .set:
            let elements = try mirror.children.map { try node($0.value, at: "\(path){}") }
            return .set(elements.sorted { precedes(inline($0), inline($1)) })

        case .dictionary:
            var entries: [(key: String, value: Node)] = []
            for pair in mirror.children {
                let parts = Array(Mirror(reflecting: pair.value).children)
                guard parts.count == 2, parts[0].label == "key", parts[1].label == "value" else {
                    throw Unrepresentable(path: path, reason: "a \(type) entry is not a (key:, value:) pair")
                }
                let key = inline(try node(parts[0].value, at: "\(path)[]"))
                entries.append((key, try node(parts[1].value, at: "\(path)[\(key)]")))
            }
            return .dictionary(entries.sorted { precedes($0.key, $1.key) })

        case .struct:
            guard !mirror.children.isEmpty else {
                throw Unrepresentable(path: path, reason: "struct \(type) shows no stored properties, so there is nothing to compare")
            }
            var fields: [(label: String, value: Node)] = []
            for child in mirror.children {
                guard let label = child.label else {
                    throw Unrepresentable(path: path, reason: "struct \(type) has an unlabelled child")
                }
                fields.append((label, try node(child.value, at: "\(path).\(label)")))
            }
            return .structure(name: type, fields: fields)

        case .enum:
            guard let payload = mirror.children.first else {
                // `String(describing:)` prints the case name only when nothing
                // overrides it; a type that does is refused rather than trusted.
                if value is CustomStringConvertible || value is CustomDebugStringConvertible
                    || value is TextOutputStreamable {
                    throw Unrepresentable(path: path, reason: "enum \(type) customises its description, so its case name cannot be read")
                }
                return .enumCase(name: String(describing: value), payload: nil)
            }
            guard let name = payload.label else {
                throw Unrepresentable(path: path, reason: "enum \(type) payload has no case label")
            }
            let parts = Mirror(reflecting: payload.value)
            if parts.displayStyle == .tuple {
                return .enumCase(name: name, payload: try parts.children.enumerated().map { index, part in
                    let label = part.label.flatMap { $0.hasPrefix(".") ? nil : $0 }
                    return (label, try node(part.value, at: "\(path).\(label ?? String(index))"))
                })
            }
            return .enumCase(name: name, payload: [(nil, try node(payload.value, at: "\(path).0"))])

        case nil:
            throw Unrepresentable(path: path, reason: unknownLeaf(type))
        case .class:
            throw Unrepresentable(path: path, reason: "class \(type): a reference type's mirror omits inherited state")
        case .tuple:
            throw Unrepresentable(path: path, reason: "a stored tuple (\(type)) is not handled")
        default:
            throw Unrepresentable(path: path, reason: "unhandled display style for \(type)")
        }
    }

    private static func unknownLeaf(_ type: String) -> String {
        type.contains("->")
            ? "a function value (\(type)) has no stored contents to compare"
            : "unknown leaf type \(type): add it to RecipeGoldenDump.leaf deliberately"
    }

    /// The leaf types, matched on the exact dynamic type so that a `Bool` is never
    /// read as an `Int` or the other way round.
    static func leaf(_ value: Any) -> String? {
        let type = Swift.type(of: value)
        if type == String.self, let string = value as? String { return quote(string) }
        if type == Bool.self, let bool = value as? Bool { return bool ? "true" : "false" }
        if type == Int.self, let int = value as? Int { return String(int) }
        if type == Double.self, let double = value as? Double { return "Double(\(double.description))" }
        if type == URL.self, let url = value as? URL { return "URL(\(quote(url.absoluteString)))" }
        if type == Data.self, let data = value as? Data { return "Data(base64: \(quote(data.base64EncodedString())))" }
        return nil
    }

    /// A mirror this can believe shows every stored property: the compiler's own,
    /// or the standard library's for its collections and `Optional`.
    ///
    /// The standard library's scalars (`Float`, `Int64`, …) are `CustomReflectable`
    /// too; one that reaches here is not a handled leaf, and is reported as that.
    static func trustedMirror(of value: Any, at path: String) throws -> Mirror {
        let type = String(reflecting: Swift.type(of: value))
        let standard = ["Swift.Array<", "Swift.Set<", "Swift.Dictionary<", "Swift.Optional<"]
        if value is CustomReflectable, !standard.contains(where: type.hasPrefix) {
            if type.hasPrefix("Swift.") || type.hasPrefix("Foundation.") {
                throw Unrepresentable(path: path, reason: unknownLeaf(type))
            }
            throw Unrepresentable(path: path, reason: "\(type) is CustomReflectable: its mirror shows what it chooses, not its stored properties")
        }
        return Mirror(reflecting: value)
    }

    static func typeName(of value: Any) -> String {
        String(reflecting: type(of: value)).replacingOccurrences(of: "DuoUpdaterCore.", with: "")
    }

    // MARK: - Text

    static func render(_ node: Node, at path: String, into lines: inout [String]) {
        switch node {
        case .leaf(let text):
            lines.append("\(path) = \(text)")
        case .none:
            lines.append("\(path) = nil")
        case .some(let wrapped):
            render(wrapped, at: path + "?", into: &lines)
        case .array(let elements):
            lines.append("\(path) = Array(count: \(elements.count))")
            for (index, element) in elements.enumerated() {
                render(element, at: "\(path)[\(index)]", into: &lines)
            }
        case .set(let elements):
            lines.append("\(path) = Set(count: \(elements.count))")
            for (index, element) in elements.enumerated() {
                render(element, at: "\(path){\(index)}", into: &lines)
            }
        case .dictionary(let entries):
            lines.append("\(path) = Dictionary(count: \(entries.count))")
            for entry in entries {
                render(entry.value, at: "\(path)[\(entry.key)]", into: &lines)
            }
        case .structure(let name, let fields):
            lines.append("\(path) = struct \(name)")
            for field in fields {
                render(field.value, at: "\(path).\(field.label)", into: &lines)
            }
        case .enumCase(let name, nil):
            lines.append("\(path) = .\(name)")
        case .enumCase(let name, let payload?):
            let signature = payload.map { "\($0.label ?? "_"):" }.joined()
            lines.append("\(path) = .\(name)(\(signature))")
            for (index, part) in payload.enumerated() {
                render(part.value, at: "\(path).\(part.label ?? String(index))", into: &lines)
            }
        }
    }

    /// One line, for a dictionary key or to sort a set by. Unambiguous for the same
    /// reason the lines are: every string inside it is quoted and escaped.
    static func inline(_ node: Node) -> String {
        switch node {
        case .leaf(let text): return text
        case .none: return "nil"
        case .some(let wrapped): return "Optional(\(inline(wrapped)))"
        case .array(let elements): return "[" + elements.map(inline).joined(separator: ", ") + "]"
        case .set(let elements): return "Set([" + elements.map(inline).joined(separator: ", ") + "])"
        case .dictionary(let entries):
            return entries.isEmpty ? "[:]"
                : "[" + entries.map { "\($0.key): \(inline($0.value))" }.joined(separator: ", ") + "]"
        case .structure(let name, let fields):
            return name + "(" + fields.map { "\($0.label): \(inline($0.value))" }.joined(separator: ", ") + ")"
        case .enumCase(let name, nil): return "." + name
        case .enumCase(let name, let payload?):
            return ".\(name)(" + payload.map { ($0.label.map { "\($0): " } ?? "") + inline($0.value) }
                .joined(separator: ", ") + ")"
        }
    }

    /// Byte order, not `String`'s `<`, which compares by canonical equivalence.
    static func precedes(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case " "..."~": out.unicodeScalars.append(scalar)
            default: out += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            }
        }
        return out + "\""
    }
}

/// The commands a golden failure prints, in one place so the message and the file
/// header cannot disagree. Run from the repository root.
enum RecipeGoldenCommand {
    static let environmentKey = "DUO_RECORD_RECIPE_GOLDENS"
    static let record = "\(environmentKey)=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests"
    static let compare = "swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests"
}
