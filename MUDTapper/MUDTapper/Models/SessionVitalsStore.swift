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
            guard let hp = hp, let max = hpMax, max > 0 else { return nil }
            return min(1.0, max(0.0, Double(hp) / Double(max)))
        }

        var manaPercent: Double? {
            guard let mana = mana, let max = manaMax, max > 0 else { return nil }
            return min(1.0, max(0.0, Double(mana) / Double(max)))
        }
    }

    private var vitalsByWorldID: [NSManagedObjectID: Vitals] = [:]
    private let queue = DispatchQueue(label: "com.mudtapper.vitals", qos: .userInitiated)

    func update(worldID: NSManagedObjectID, with variables: [String: String]) {
        queue.async {
            var current = self.vitalsByWorldID[worldID] ?? Vitals(hp: nil, hpMax: nil, mana: nil, manaMax: nil, updatedAt: Date())
            // Map common MSDP variable names
            // Accept multiple aliases to maximize compatibility
            if let hp = self.firstInt(forKeys: ["HEALTH", "HP"], in: variables) { current.hp = hp }
            if let hpMax = self.firstInt(forKeys: ["HEALTH_MAX", "MAX_HEALTH", "HP_MAX", "MAX_HP"], in: variables) { current.hpMax = hpMax }
            if let mana = self.firstInt(forKeys: ["MANA", "MN"], in: variables) { current.mana = mana }
            if let manaMax = self.firstInt(forKeys: ["MANA_MAX", "MAX_MANA", "MN_MAX", "MAX_MN"], in: variables) { current.manaMax = manaMax }

            current.updatedAt = Date()
            self.vitalsByWorldID[worldID] = current

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .vitalsDidUpdate, object: worldID)
            }
        }
    }

    func vitals(for worldID: NSManagedObjectID) -> Vitals? {
        return queue.sync { vitalsByWorldID[worldID] }
    }

    private func firstInt(forKeys keys: [String], in dict: [String: String]) -> Int? {
        for key in keys {
            if let v = dict[key], let i = Int(v) { return i }
            // Be tolerant of lowercase server keys
            if let v = dict[key.lowercased()], let i = Int(v) { return i }
        }
        return nil
    }
}

extension Notification.Name {
    static let vitalsDidUpdate = Notification.Name("sessionVitalsDidUpdate")
}


