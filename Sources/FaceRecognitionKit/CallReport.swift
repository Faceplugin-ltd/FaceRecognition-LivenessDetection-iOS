import Foundation

/// One timed SDK call. `detail` is the short result of that call; `ok` is false when this step
/// stopped the action.
public struct CallStep: Equatable {
    public let name: String
    public let ms: Double
    public let detail: String
    public let ok: Bool

    public init(name: String, ms: Double, detail: String, ok: Bool = true) {
        self.name = name
        self.ms = ms
        self.detail = detail
        self.ok = ok
    }
}

/// Shown after an action finishes: total time, each call, progress, detail and overall outcome.
/// Stored with every enrolled person, so it round-trips as JSON.
public struct CallReport: Equatable {
    public let function: String
    public let steps: [CallStep]
    public let progress: String
    public let detail: String
    public let success: Bool
    /// Wall-clock time the action finished, in milliseconds since 1970.
    public let finishedAt: Double

    public init(
        function: String,
        steps: [CallStep],
        progress: String,
        detail: String,
        success: Bool = true,
        finishedAt: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.function = function
        self.steps = steps
        self.progress = progress
        self.detail = detail
        self.success = success
        self.finishedAt = finishedAt
    }

    public var totalMs: Double { steps.reduce(0) { $0 + $1.ms } }

    public func toJson() -> String {
        let payload: [String: Any] = [
            "function": function,
            "progress": progress,
            "detail": detail,
            "success": success,
            "finishedAt": finishedAt,
            "steps": steps.map { step in
                ["name": step.name, "ms": step.ms, "detail": step.detail, "ok": step.ok] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    /// Returns nil for a person enrolled before reports were stored, or for unreadable JSON.
    public static func fromJson(_ json: String?) -> CallReport? {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let rawSteps = obj["steps"] as? [[String: Any]] ?? []
        return CallReport(
            function: obj["function"] as? String ?? "",
            steps: rawSteps.map { step in
                CallStep(
                    name: step["name"] as? String ?? "",
                    ms: step["ms"] as? Double ?? 0,
                    detail: step["detail"] as? String ?? "",
                    ok: step["ok"] as? Bool ?? true
                )
            },
            progress: obj["progress"] as? String ?? "",
            detail: obj["detail"] as? String ?? "",
            success: obj["success"] as? Bool ?? true,
            finishedAt: obj["finishedAt"] as? Double ?? 0
        )
    }
}
