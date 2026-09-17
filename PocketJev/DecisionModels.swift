import Foundation
import UIKit

struct DecisionResult: Sendable, Equatable {
    let choice: String
    let probabilities: [String: Double]
    let optionLogits: [String: Double]
    let latencyMS: Double
    let promptTokens: Int
}

struct ContinuousCaptureSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct OptionPreset: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var options: [String]

    static var yesNoUnknown: OptionPreset {
        let unknown = AppLanguage.text("判別不能", "UNKNOWN")
        return OptionPreset(
            id: "default-yes-no-unknown",
            name: "YES / NO / \(unknown)",
            options: ["YES", "NO", unknown]
        )
    }
}

enum ModelLoadState: Equatable {
    case idle
    case loading(progress: Double)
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum PocketJevError: LocalizedError {
    case modelNotReady
    case invalidOptions
    case invalidLabelToken(String)
    case cameraUnavailable
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            AppLanguage.text("AIモデルがまだ準備できていません。", "The AI model is not ready yet.")
        case .invalidOptions:
            AppLanguage.text("選択肢は2〜26個の空でない値にしてください。", "Use 2 to 26 non-empty options.")
        case .invalidLabelToken(let label):
            AppLanguage.text(
                "回答ラベル \(label) を1 tokenとして扱えませんでした。",
                "Answer label \(label) could not be represented as a single token."
            )
        case .cameraUnavailable:
            AppLanguage.text("カメラを利用できません。", "The camera is unavailable.")
        case .imageEncodingFailed:
            AppLanguage.text("判定用画像を作成できませんでした。", "Could not prepare the image for analysis.")
        }
    }
}

enum DecisionMath {
    static func softmax(_ scores: [Double]) -> [Double] {
        guard let maximum = scores.max(), !scores.isEmpty else { return [] }
        let exps = scores.map { Foundation.exp($0 - maximum) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return Array(repeating: 0, count: scores.count) }
        return exps.map { $0 / sum }
    }
}
