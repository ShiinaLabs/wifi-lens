// Orders .xcstrings keys the way Xcode's string-catalog writer does.
//
// Xcode writes catalog keys sorted by `NSString.localizedStandardCompare`.
// Python's standard library has no ICU collation, so `format_xcstrings.py`
// delegates the ordering here instead of approximating it.
//
// The comparison uses a fixed locale rather than the developer's current one,
// so the canonical bytes are the same on every machine. That fixed-locale
// comparison produces the same order as `localizedStandardCompare` for every
// key in this repository's catalogs.
//
// Keys are exchanged NUL-separated on stdin and stdout, because a catalog key
// may itself contain a newline.

import Foundation

let options: String.CompareOptions = [.numeric, .caseInsensitive, .widthInsensitive, .forcedOrdering]
let locale = Locale(identifier: "en_US")

let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
var keys = input.components(separatedBy: "\0")
if keys.last == "" {
    keys.removeLast()
}

let ordered = keys.sorted {
    $0.compare($1, options: options, range: nil, locale: locale) == .orderedAscending
}

FileHandle.standardOutput.write(ordered.joined(separator: "\0").data(using: .utf8)!)
