import Foundation

/// Reads what `claude setup-token` prints to its terminal. Hop runs the command itself and picks the token
/// out of the output, so the user never copies or pastes it. Pure, so the parsing can be tested.
public enum SetupTokenOutput {
    /// Removes terminal escape sequences (colors, cursor moves, hyperlinks, window titles) and turns carriage
    /// returns into newlines, leaving only the text a person would see. The screen is drawn with cursor moves
    /// where a person sees spaces and line breaks, so those become a space or a newline.
    public static func stripEscapes(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            switch scalar {
            case "\u{1B}":
                guard let kind = scalars.next() else { break }
                switch kind {
                case "[":
                    // CSI: parameters, then one final byte in @…~.
                    var final: Unicode.Scalar?
                    while let next = scalars.next() {
                        if (0x40...0x7E).contains(next.value) { final = next; break }
                    }
                    switch final {
                    case "C": out.append(" ")                                   // cursor forward
                    case "A", "B", "E", "F", "G", "H", "d", "f": out.append("\n")  // cursor to another line/column
                    default: break
                    }
                case "]", "P", "X", "^", "_":
                    // OSC / DCS / SOS / PM / APC: a string ended by BEL or ESC \.
                    while let next = scalars.next() {
                        if next == "\u{07}" { break }
                        if next == "\u{1B}" { _ = scalars.next(); break }
                    }
                default:
                    break   // a two-character escape: drop both
                }
            case "\r":
                out.append("\n")
            case "\n", "\t":
                out.append(scalar)
            default:
                if scalar.value >= 0x20 && scalar.value != 0x7F { out.append(scalar) }
            }
        }
        return String(out)
    }

    /// The setup-token in the output so far, or nil until it has been printed in full. A token counts only
    /// once something that can't be part of it follows, so a read that stops mid-token never returns half.
    public static func token(in output: String) -> String? {
        let text = stripEscapes(output)
        guard let regex = try? NSRegularExpression(pattern: "sk-ant-oat01-[A-Za-z0-9_-]+(?=[^A-Za-z0-9_-])") else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.reversed().lazy
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .first { $0.count > SetupToken.minLength }
    }

    /// The last line of visible text, to explain a run that ended without a token.
    public static func lastLine(of output: String) -> String? {
        stripEscapes(output)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}
