import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class DecisionViewModel {
    let camera = CameraService()
    private let engine = JevDecisionEngine()
    private let presetsKey = "pocketjev.optionPresets.v1"

    var modelState: ModelLoadState = .idle
    var showModelStatus = true
    var selectedImage: UIImage?
    var question = AppLanguage.text(
        "画像内の主な対象はフレーム内に収まっていますか？",
        "Is the main subject fully inside the frame?"
    )
    var optionPresets: [OptionPreset]
    var selectedOptionPresetID: String

    var result: DecisionResult?
    var continuousResultSnapshot: ContinuousCaptureSnapshot?
    var continuousPendingSnapshot: ContinuousCaptureSnapshot?
    var errorMessage: String?
    var isAnalyzing = false
    var continuousEnabled = false
    var continuousInterval = 2.0

    private var continuousTask: Task<Void, Never>?
    private var modelHideTask: Task<Void, Never>?

    init() {
        let presets: [OptionPreset]
        if
            let data = UserDefaults.standard.data(forKey: presetsKey),
            let decoded = try? JSONDecoder().decode([OptionPreset].self, from: data),
            !decoded.isEmpty
        {
            presets = decoded.map { preset in
                // Keep user-created presets untouched, but make the built-in
                // default follow the current iPhone/app language.
                preset.id == OptionPreset.yesNoUnknown.id ? .yesNoUnknown : preset
            }
        } else {
            presets = [.yesNoUnknown]
        }
        optionPresets = presets
        selectedOptionPresetID = presets.first?.id ?? OptionPreset.yesNoUnknown.id
    }

    var options: [String] {
        optionPresets.first(where: { $0.id == selectedOptionPresetID })?.options
            ?? OptionPreset.yesNoUnknown.options
    }

    func startCamera() async {
        await camera.start()
    }

    func prepareModel() {
        guard !modelState.isReady else { return }
        modelHideTask?.cancel()
        showModelStatus = true
        modelState = .loading(progress: 0)
        errorMessage = nil

        Task {
            do {
                try await engine.load { [weak self] progress in
                    Task { @MainActor in
                        self?.modelState = .loading(progress: progress)
                    }
                }
                modelState = .ready
                modelHideTask?.cancel()
                modelHideTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self?.showModelStatus = false
                }
            } catch {
                modelState = .failed(error.localizedDescription)
                showModelStatus = true
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectOptionPreset(id: String) {
        guard optionPresets.contains(where: { $0.id == id }) else { return }
        selectedOptionPresetID = id
        result = nil
    }

    func upsertOptionPreset(_ preset: OptionPreset) {
        let cleanedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOptions = preset.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleanedName.isEmpty,
              (2...26).contains(cleanedOptions.count),
              cleanedOptions.allSatisfy({ !$0.isEmpty }),
              Set(cleanedOptions).count == cleanedOptions.count
        else { return }

        let cleaned = OptionPreset(id: preset.id, name: cleanedName, options: cleanedOptions)
        if let index = optionPresets.firstIndex(where: { $0.id == cleaned.id }) {
            optionPresets[index] = cleaned
        } else {
            optionPresets.append(cleaned)
        }
        selectedOptionPresetID = cleaned.id
        result = nil
        persistOptionPresets()
    }

    func deleteOptionPresets(at offsets: IndexSet) {
        guard optionPresets.count > 1 else { return }
        let ids = offsets.compactMap { optionPresets.indices.contains($0) ? optionPresets[$0].id : nil }
        for index in offsets.sorted(by: >) where optionPresets.indices.contains(index) {
            optionPresets.remove(at: index)
        }
        if ids.contains(selectedOptionPresetID) {
            selectedOptionPresetID = optionPresets.first?.id ?? OptionPreset.yesNoUnknown.id
        }
        result = nil
        persistOptionPresets()
    }

    private func persistOptionPresets() {
        guard let data = try? JSONEncoder().encode(optionPresets) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }

    func captureAndAnalyze() async {
        guard !isAnalyzing else { return }
        do {
            let image = try await camera.capture()
            if continuousEnabled {
                selectedImage = nil
                let snapshot = ContinuousCaptureSnapshot(image: image)
                continuousPendingSnapshot = snapshot
                await analyze(image, continuousSnapshot: snapshot)
            } else {
                selectedImage = image
                await analyze(image)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func analyzeSelectedImage() async {
        guard let selectedImage else {
            errorMessage = AppLanguage.text(
                "先にカメラ撮影か写真選択をしてください。",
                "Take a photo or choose one from Photos first."
            )
            return
        }
        await analyze(selectedImage)
    }

    func setPhotoData(_ data: Data) async {
        guard let image = UIImage(data: data) else {
            errorMessage = AppLanguage.text("写真を読み込めませんでした。", "Could not load the photo.")
            return
        }
        selectedImage = image
        await analyze(image)
    }

    func setContinuous(_ enabled: Bool) {
        continuousEnabled = enabled
        continuousTask?.cancel()
        continuousTask = nil
        if enabled {
            selectedImage = nil
            result = nil
            continuousResultSnapshot = nil
            continuousPendingSnapshot = nil
        }
        if !enabled {
            continuousResultSnapshot = nil
            continuousPendingSnapshot = nil
        }
        guard enabled else { return }

        continuousTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.modelState.isReady && !self.isAnalyzing {
                    await self.captureAndAnalyze()
                }
                let ns = UInt64(max(1, self.continuousInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    private func analyze(
        _ image: UIImage,
        continuousSnapshot: ContinuousCaptureSnapshot? = nil
    ) async {
        guard modelState.isReady else {
            errorMessage = AppLanguage.text("先にAIモデルを準備してください。", "Prepare the AI model first.")
            return
        }
        let cleanOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (2...26).contains(cleanOptions.count), cleanOptions.allSatisfy({ !$0.isEmpty }) else {
            errorMessage = PocketJevError.invalidOptions.localizedDescription
            return
        }

        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        do {
            let url = try makeInferenceImage(image)
            defer { try? FileManager.default.removeItem(at: url) }

            let newResult = try await engine.decide(
                imageURL: url,
                question: question,
                options: cleanOptions,
                maxEdge: 512
            )
            result = newResult

            if let continuousSnapshot {
                if continuousEnabled {
                    continuousResultSnapshot = continuousSnapshot
                }
                if continuousPendingSnapshot?.id == continuousSnapshot.id {
                    continuousPendingSnapshot = nil
                }
            }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeInferenceImage(_ image: UIImage) throws -> URL {
        let maxEdge: CGFloat = 512
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        guard let data = resized.jpegData(compressionQuality: 0.9) else {
            throw PocketJevError.imageEncodingFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocketjev-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}
