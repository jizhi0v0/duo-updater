import SwiftUI
import DuoUpdaterCore

/// The request log's filter, as removable capsules plus one plain input.
///
/// The first version coloured a single text field's contents through the
/// `NSTextField` field editor, and lost: AppKit owns selection and attribute
/// state there, so tabbing in selected the whole query, clicking back in
/// dropped the colouring, and every fix uncovered the next case. A committed
/// filter is not text being edited — it is a thing with a remove button — so
/// this draws it as one and leaves the field holding only what is being typed.
///
/// **The string is still the source of truth.** Capsules are just
/// ``RequestQuery/tokenize(_:)`` of the same text the chips edit and
/// `duo events --filter` takes, so nothing here can drift from what actually
/// gets queried.
struct QueryTokenField: View {
    /// The pinned filters. Only `key:value` tokens live here.
    @Binding var text: String
    /// The free text being typed. It filters live and never becomes a capsule:
    /// a search word is something you keep editing, not a thing with a remove
    /// button.
    @Binding var draft: String
    /// Which tokens the parser will not act on, so they can be drawn as the
    /// warnings they are rather than as working filters.
    let ignored: Set<String>
    var placeholder: String

    @FocusState private var focused: Bool

    private var tokens: [String] { RequestQuery.tokenize(text) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Capsules and the input are one flow, not two columns. Split
            // across the HStack they each claimed half the width, so the
            // insertion point began at the middle of the field with a gap in
            // front of it; here the input simply follows the last capsule and
            // wraps with them.
            FlowLayout(spacing: 5) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    capsule(token, at: index)
                }
                TextField("", text: $draft, prompt: tokens.isEmpty
                          ? Text(verbatim: placeholder) : Text(verbatim: ""))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    // Wide enough to be worth clicking into, and to keep the
                    // caret off the capsule beside it.
                    .frame(minWidth: 160)
                    .focused($focused)
                    .onSubmit(commit)
                    // A space ends a token, the way it does in every filter bar
                    // — but only outside quotes, so `app:"Visual Studio"`
                    // survives it.
                    .onChange(of: draft) { _, new in
                        guard new.hasSuffix(" "),
                              new.filter({ $0 == "\"" }).count.isMultiple(of: 2)
                        else { return }
                        commit()
                    }
                    // Backspace on an empty field takes the last capsule back, so
                    // a typo is one key away from being fixed rather than a mouse
                    // trip.
                    .onKeyPress(.delete) {
                        guard draft.isEmpty, let last = tokens.last else { return .ignored }
                        text = tokens.dropLast().joined(separator: " ")
                        draft = last
                        return .handled
                    }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !text.isEmpty || !draft.isEmpty {
                Button {
                    text = ""
                    draft = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // A capsule is taller than a bare text line, so the field grew by a few
        // points the moment the first filter landed and the whole table stepped
        // down with it. The row is sized for the capsule from the start, empty
        // or not; only wrapping to a second line is allowed to change it.
        .frame(minHeight: 28)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(focused ? Color.accentColor.opacity(0.6)
                                  : Color(nsColor: .separatorColor), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    /// One committed filter. The key is dimmed and the value is not, which is
    /// the whole reason the old version wanted syntax colouring.
    private func capsule(_ token: String, at index: Int) -> some View {
        let parts = Self.split(token)
        let isIgnored = ignored.contains(token)
        return HStack(spacing: 3) {
            if let key = parts.key {
                Text(key)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(parts.value)
                .font(.system(size: 11.5))
                .foregroundStyle(isIgnored ? Color.orange : Color.primary)
            Button {
                var remaining = tokens
                remaining.remove(at: index)
                text = remaining.joined(separator: " ")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(isIgnored
            ? Color.orange.opacity(0.16)
            : Color.accentColor.opacity(0.18)))
        .overlay(Capsule().strokeBorder(isIgnored
            ? Color.orange.opacity(0.5)
            : Color.accentColor.opacity(0.45), lineWidth: 1))
        .help(isIgnored
              ? String(localized: "Not a filter Duo Updater knows — this narrows nothing.")
              : token)
    }

    /// `host:apple.com` → ("host:", "apple.com"); a bare word has no key.
    static func split(_ token: String) -> (key: String?, value: String) {
        for separator in [":", ">", "<"] {
            guard let index = token.firstIndex(of: Character(separator)),
                  index != token.startIndex else { continue }
            let key = String(token[token.startIndex...index])
            let value = String(token[token.index(after: index)...])
                .replacingOccurrences(of: "\"", with: "")
            guard !value.isEmpty else { continue }
            return (key, value)
        }
        return (nil, token.replacingOccurrences(of: "\"", with: ""))
    }

    /// Pins the `key:value` tokens out of the draft and leaves the rest alone.
    ///
    /// A bare word stays where it was typed: it is a search, and it is already
    /// filtering — freezing it into a capsule the instant you hit space turns
    /// "keep typing to narrow" into "delete a chip and start again". Only a
    /// structured token is a thing worth pinning, which is also the only kind
    /// the chips produce.
    private func commit() {
        var pinned = tokens
        var rest: [String] = []
        for token in RequestQuery.tokenize(draft) {
            if Self.split(token).key != nil { pinned.append(token) } else { rest.append(token) }
        }
        guard pinned.count != tokens.count else { return }
        text = pinned.joined(separator: " ")
        // A trailing space, so typing carries on where it left off.
        draft = rest.isEmpty ? "" : rest.joined(separator: " ") + " "
    }
}
