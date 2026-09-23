import Foundation

/// The five moods offered by the picker. Raw values are stable identifiers and
/// are what gets persisted — renaming a case would orphan existing entries, so
/// the raw strings must never change once entries exist in the wild.
enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
    case rough
    case low
    case steady
    case good
    case bright

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .rough:  return "😞"
        case .low:    return "😕"
        case .steady: return "😐"
        case .good:   return "🙂"
        case .bright: return "😄"
        }
    }

    var label: String {
        switch self {
        case .rough:  return "Rough"
        case .low:    return "Low"
        case .steady: return "Steady"
        case .good:   return "Good"
        case .bright: return "Bright"
        }
    }
}
