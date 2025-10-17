import Foundation
import CoreData

final class SessionVitalsStore {
    static let shared = SessionVitalsStore()
    private init() {}

    struct Vitals {
        var hp: Int?
        var hpMax: Int?
        var mana: Int?
        var manaMax: Int?
        var updatedAt: Date

        var hpPercent: Double? {
            guard let hp = hp, let maxValue = hpMax, maxValue > 0 else { return nil }
            return Swift.min(1.0, Swift.max(0.0, Double(hp) / Double(maxValue)))
        }

        var manaPercent: Double? {
            guard let mana = mana, let maxValue = manaMax, maxValue > 0 else { return nil }
            return Swift.min(1.0, Swift.max(0.0, Double(mana) / Double(maxValue)))
        }
    }

    private var vitalsByWorldID: [NSManagedObjectID: Vitals] = [:]
    // Use concurrent queue with barrier for thread-safe reads and writes
    private let queue = DispatchQueue(label: "com.mudtapper.vitals", qos: .userInitiated, attributes: .concurrent)

    func update(worldID: NSManagedObjectID, with variables: [String: String]) {
        // Use barrier flag for thread-safe writes
        queue.async(flags: .barrier) {
            var current = self.vitalsByWorldID[worldID] ?? Vitals(hp: nil, hpMax: nil, mana: nil, manaMax: nil, updatedAt: Date())
            // Build a normalized view of server variables for tolerant matching
            // Normalize by lowercasing and stripping non-alphanumerics so
            //   "HP_MAX", "hpMax", "hpmax" → "hpmax"
            let normalizedDict: [String: String] = {
                var out: [String: String] = [:]
                for (k, v) in variables {
                    out[Self.normalizeKey(k)] = v
                }
                return out
            }()

            // Per-world overrides (exact strings supplied by user, matched loosely)
            let prefix = "MSDP.Mapping.\(worldID.uriRepresentation().absoluteString)."
            let hpOverride = UserDefaults.standard.string(forKey: prefix + "HP")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hpMaxOverride = UserDefaults.standard.string(forKey: prefix + "HP_MAX")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let manaOverride = UserDefaults.standard.string(forKey: prefix + "MANA")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let manaMaxOverride = UserDefaults.standard.string(forKey: prefix + "MANA_MAX")?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Helper to read using tolerant alias matching
            func readInt(aliases: [String]) -> Int? {
                // Prefer exact case-insensitive matches from original dict, then normalized aliases
                if let val = self.firstInt(forKeys: aliases, in: variables) { return val }
                let normalizedAliases = aliases.map { Self.normalizeKey($0) }
                for alias in normalizedAliases {
                    if let v = normalizedDict[alias], let i = Int(v) { return i }
                }
                return nil
            }

            if let key = hpOverride, !key.isEmpty {
                if let i = readInt(aliases: [key]) { current.hp = i }
            } else if let i = readInt(aliases: ["HEALTH", "HP", "HITPOINTS", "HIT_POINTS", "HITS", "H"]) { current.hp = i }

            if let key = hpMaxOverride, !key.isEmpty {
                if let i = readInt(aliases: [key]) { current.hpMax = i }
            } else if let i = readInt(aliases: ["HEALTH_MAX", "MAX_HEALTH", "HP_MAX", "MAX_HP", "MAXHP", "HITPOINTS_MAX", "MAX_HITPOINTS", "HPMAX"]) { current.hpMax = i }

            if let key = manaOverride, !key.isEmpty {
                if let i = readInt(aliases: [key]) { current.mana = i }
            } else if let i = readInt(aliases: ["MANA", "MN", "MP", "SPELLPOINTS", "SP", "M"]) { current.mana = i }

            if let key = manaMaxOverride, !key.isEmpty {
                if let i = readInt(aliases: [key]) { current.manaMax = i }
            } else if let i = readInt(aliases: ["MANA_MAX", "MAX_MANA", "MN_MAX", "MAX_MN", "MAXMP", "MP_MAX", "MAX_MP", "SPELLPOINTS_MAX", "SP_MAX", "MANAMAX"]) { current.manaMax = i }

            // Fallback: Parse compact values like "123/456" commonly sent for vitals
            func parsePair(_ value: String) -> (Int, Int)? {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2, let a = Int(parts[0].trimmingCharacters(in: .whitespaces)), let b = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    return (a, b)
                }
                return nil
            }
            if (current.hp == nil || current.hpMax == nil) {
                if let v = normalizedDict[Self.normalizeKey("HEALTH")] ?? normalizedDict[Self.normalizeKey("HP")], let (a,b) = parsePair(v) {
                    if current.hp == nil { current.hp = a }
                    if current.hpMax == nil { current.hpMax = b }
                }
            }
            if (current.mana == nil || current.manaMax == nil) {
                if let v = normalizedDict[Self.normalizeKey("MANA")] ?? normalizedDict[Self.normalizeKey("MN")], let (a,b) = parsePair(v) {
                    if current.mana == nil { current.mana = a }
                    if current.manaMax == nil { current.manaMax = b }
                }
            }

            // If server didn't supply maxima, fall back to rolling maxima from observed values
            if current.hpMax == nil, let hp = current.hp {
                current.hpMax = hp
            } else if let hp = current.hp, let maxVal = current.hpMax, hp > maxVal {
                current.hpMax = hp
            }

            if current.manaMax == nil, let mana = current.mana {
                current.manaMax = mana
            } else if let mana = current.mana, let maxVal = current.manaMax, mana > maxVal {
                current.manaMax = mana
            }

            current.updatedAt = Date()
            self.vitalsByWorldID[worldID] = current

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .vitalsDidUpdate, object: worldID)
            }
        }
    }

    func vitals(for worldID: NSManagedObjectID) -> Vitals? {
        // Concurrent read - safe because we use barriers for writes
        return queue.sync { vitalsByWorldID[worldID] }
    }
    
    // MARK: - Cleanup
    
    /// Clear vitals for a specific world (e.g., when disconnecting)
    func clearVitals(for worldID: NSManagedObjectID) {
        queue.async(flags: .barrier) {
            self.vitalsByWorldID.removeValue(forKey: worldID)
        }
    }
    
    /// Clear all stored vitals
    func clearAllVitals() {
        queue.async(flags: .barrier) {
            self.vitalsByWorldID.removeAll()
        }
    }

    private func firstInt(forKeys keys: [String], in dict: [String: String]) -> Int? {
        for key in keys {
            if let v = dict[key], let i = Int(v) { return i }
            // Be tolerant of lowercase server keys
            if let v = dict[key.lowercased()], let i = Int(v) { return i }
        }
        return nil
    }

    private static func normalizeKey(_ key: String) -> String {
        let lowered = key.lowercased()
        return lowered.filter { $0.isLetter || $0.isNumber }
    }
}

extension Notification.Name {
    static let vitalsDidUpdate = Notification.Name("sessionVitalsDidUpdate")
}


