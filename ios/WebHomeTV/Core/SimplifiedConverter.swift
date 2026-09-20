import Foundation

/// Simplified/Traditional Chinese conversion.
/// Stage one: a small static mapping for common pairs; full table bundled later as an asset.
enum SimplifiedConverter {
    static func s2t(_ text: String) -> String {
        var out = text
        let map: [Character: Character] = [
            "你": "妳", "为": "為", "说": "說", "这": "這", "书": "書",
            "爱": "愛", "门": "門", "马": "馬", "鱼": "魚", "华": "華",
        ]
        for (simplified, traditional) in map {
            out = out.replacingOccurrences(of: String(simplified), with: String(traditional))
        }
        return out
    }
    static func t2s(_ text: String) -> String {
        var out = text
        let map: [Character: Character] = [
            "妳": "你", "為": "为", "說": "说", "這": "这", "書": "书",
            "愛": "爱", "門": "门", "馬": "马", "魚": "鱼", "華": "华",
        ]
        for (traditional, simplified) in map {
            out = out.replacingOccurrences(of: String(traditional), with: String(simplified))
        }
        return out
    }
}
