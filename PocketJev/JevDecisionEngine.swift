import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

actor JevDecisionEngine {
    static let modelID = "mlx-community/Qwen3-VL-2B-Instruct-4bit"

    private let configuration = ModelConfiguration(
        id: modelID,
        defaultPrompt: "",
        extraEOSTokens: ["<|im_end|>"]
    )

    private var container: ModelContainer?

    func load(progress: @Sendable @escaping (Double) -> Void) async throws {
        if container != nil {
            progress(1)
            return
        }

        Memory.cacheLimit = 20 * 1024 * 1024

        let downloader = #hubDownloader()
        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let loaded = try await VLMModelFactory.shared.loadContainer(
            from: downloader,
            using: tokenizerLoader,
            configuration: configuration
        ) { value in
            progress(value.fractionCompleted)
        }

        container = loaded
        progress(1)
    }

    func decide(
        imageURL: URL,
        question: String,
        options: [String],
        maxEdge: Int = 512
    ) async throws -> DecisionResult {
        guard let container else { throw PocketJevError.modelNotReady }
        let cleanOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (2...26).contains(cleanOptions.count), cleanOptions.allSatisfy({ !$0.isEmpty }) else {
            throw PocketJevError.invalidOptions
        }

        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").prefix(cleanOptions.count).map(String.init)
        let list = zip(letters, cleanOptions).map { "\($0): \($1)" }.joined(separator: "\n")
        let prompt = """
        \(question)

        Options:
        \(list)

        Reply with ONLY the uppercase option letter. Do not explain.
        """

        let system = """
        You are a visual decision engine. Inspect only what is actually visible in the image.
        Do not assume that a requested or expected feature exists. If the evidence is insufficient,
        prefer an explicit unknown/unclear option when one is provided. Reply with one uppercase letter only.
        """

        let input = UserInput(
            chat: [
                .system(system),
                .user(prompt, images: [.url(imageURL)]),
            ],
            processing: .init(resize: .init(width: maxEdge, height: maxEdge)),
            additionalContext: ["enable_thinking": false]
        )

        let started = ContinuousClock.now
        let scored: ([Double], Int) = try await container.perform(nonSendable: input) {
            context, userInput in
            let lmInput = try await context.processor.prepare(input: userInput)
            let cache = try context.model.newCache(parameters: nil)

            let logits: MLXArray
            switch try context.model.prepare(
                lmInput,
                cache: cache,
                state: nil,
                prefill: .init()
            ) {
            case .logits(let output):
                logits = output.logits

            case .tokens(let tokens):
                logits = withPreparedCache(cache, lengths: tokens.sequenceLengths) {
                    context.model(
                        tokens[text: .newAxis],
                        cache: cache.isEmpty ? nil : cache,
                        state: nil
                    ).logits
                }
            }

            let last = logits[0..., -1, 0...]
            MLX.eval(last)
            let row = last.asArray(Float.self)

            let tokenIDs = try letters.map { label -> Int in
                let ids = context.tokenizer.encode(text: label, addSpecialTokens: false)
                guard ids.count == 1, let id = ids.first else {
                    throw PocketJevError.invalidLabelToken(label)
                }
                return id
            }

            let scores = tokenIDs.map { Double(row[$0]) }
            return (scores, lmInput.text.tokens.size)
        }

        let elapsed = started.duration(to: .now)
        let latencyMS = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

        let probabilities = DecisionMath.softmax(scored.0)
        guard let winner = probabilities.indices.max(by: { probabilities[$0] < probabilities[$1] }) else {
            throw PocketJevError.invalidOptions
        }

        return DecisionResult(
            choice: cleanOptions[winner],
            probabilities: Dictionary(uniqueKeysWithValues: zip(cleanOptions, probabilities)),
            optionLogits: Dictionary(uniqueKeysWithValues: zip(cleanOptions, scored.0)),
            latencyMS: latencyMS,
            promptTokens: scored.1
        )
    }
}
