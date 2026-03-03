import Foundation

struct SemanticVersion: Comparable {
    let parts: [Int]

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<count {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func parse(from raw: String) -> SemanticVersion? {
        let pattern = #"(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range) else { return nil }

        var nums: [Int] = []
        for idx in 1...3 {
            let r = match.range(at: idx)
            if r.location == NSNotFound { continue }
            if let swiftRange = Range(r, in: raw), let num = Int(raw[swiftRange]) {
                nums.append(num)
            }
        }

        return nums.isEmpty ? nil : SemanticVersion(parts: nums)
    }
}
