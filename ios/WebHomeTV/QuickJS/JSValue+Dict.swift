import Foundation
import JavaScriptCore

extension JSValue {
    /// Convert a JS value (object/array/string/primitive) to a Swift-native dictionary.
    /// Named distinctly to avoid colliding with `JSValue.toDictionary()`.
    func toBridgeDictionary() -> [String: Any] {
        guard !isUndefined, !isNull else { return [:] }
        guard let obj = toObject() else { return [:] }
        if let dict = obj as? [String: Any] { return dict }
        return ["value": obj]
    }
}
