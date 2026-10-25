import Foundation

/// Text from the network, made safe to print to a terminal.
///
/// A version string or a response body a vendor controls can carry escape
/// sequences: OSC 52 writes to the clipboard, OSC 0/2 retitles the window, CSI
/// moves the cursor over what was printed before. `duo verify` prints both.
public enum TerminalText {

    /// `s` without terminal escape sequences (`CLIToolCommandRunner.stripEscapes`)
    /// and without the control characters that remain: C0 (`\n` and `\r` too, so a
    /// value cannot start a line of its own), DEL and C1, whose `U+009B` and
    /// `U+009D` are single-character CSI and OSC on a terminal that honours them.
    /// Tab survives. Callers print multi-line text a line at a time.
    public static func printable(_ s: String) -> String {
        let stripped = CLIToolCommandRunner.stripEscapes(s)
        guard stripped.unicodeScalars.contains(where: isStripped) else { return stripped }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: stripped.unicodeScalars.filter { !isStripped($0) })
        return String(scalars)
    }

    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        scalar != "\t" && scalar.properties.generalCategory == .control
    }
}
