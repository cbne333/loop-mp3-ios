import Foundation

enum RepeatMode: String, Codable, CaseIterable, Identifiable {
    case off, one, all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "반복 끔"
        case .one: return "한 곡 반복"
        case .all: return "목록 반복"
        }
    }

    // Manual next ignores single-track repeat. Automatic completion respects it.
    func nextIndex(after index: Int, count: Int, automatic: Bool) -> Int? {
        guard count > 0, (0..<count).contains(index) else { return nil }
        if automatic && self == .one { return index }
        if index + 1 < count { return index + 1 }
        return self == .all ? 0 : nil
    }
}
