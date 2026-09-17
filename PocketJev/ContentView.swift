import PhotosUI
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: DecisionViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showingOptionEditor = false
    @State private var showingAbout = false
    @FocusState private var questionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    brandHeader
                    if viewModel.showModelStatus {
                        modelCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    cameraCard
                    questionCard
                    optionPickerCard
                    resultCard
                    controlsCard

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showModelStatus)
            .task {
                await viewModel.startCamera()
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        await viewModel.setPhotoData(data)
                    }
                }
            }
            .sheet(isPresented: $showingOptionEditor) {
                OptionPresetEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppLanguage.text("完了", "Done")) { questionFocused = false }
                }
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text("PocketJev")
                .font(.headline.weight(.semibold))

            Spacer()

            Button {
                questionFocused = false
                showingAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguage.text("PocketJevについて", "About PocketJev"))
        }
        .padding(.horizontal, 2)
        .frame(height: 24)
    }

    private var modelCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Qwen3-VL 2B · 4bit")
                        .font(.headline)
                    Text(modelStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !viewModel.modelState.isReady {
                    Button(AppLanguage.text("AI準備", "Prepare AI")) { viewModel.prepareModel() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isModelLoading)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                }
            }

            if case .loading(let progress) = viewModel.modelState {
                ProgressView(value: progress)
                    .padding(.top, 8)
            }
        } label: {
            Label(AppLanguage.text("端末内AI", "On-device AI"), systemImage: "cpu")
        }
    }

    private var cameraCard: some View {
        VStack(spacing: 10) {
            ZStack {
                CameraPreview(session: viewModel.camera.session)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                if let selected = viewModel.selectedImage {
                    Image(uiImage: selected)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                viewModel.selectedImage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(8)
                        }
                }

                if viewModel.isAnalyzing {
                    ProgressView(AppLanguage.text("判定中…", "Analyzing…"))
                        .padding(12)
                        .background(.black.opacity(0.7), in: Capsule())
                }
            }

            HStack {
                Button {
                    Task { await viewModel.captureAndAnalyze() }
                } label: {
                    Label(AppLanguage.text("撮って判定", "Capture & Decide"), systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAnalyzing)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(AppLanguage.text("写真", "Photos"), systemImage: "photo")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var questionCard: some View {
        GroupBox {
            TextField(AppLanguage.text("質問", "Question"), text: $viewModel.question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .focused($questionFocused)
                .submitLabel(.done)
                .onSubmit { questionFocused = false }
        } label: {
            Label(AppLanguage.text("質問", "Question"), systemImage: "text.bubble")
        }
    }

    private var optionPickerCard: some View {
        GroupBox {
            HStack(spacing: 10) {
                Picker(
                    AppLanguage.text("選択肢", "Options"),
                    selection: Binding(
                        get: { viewModel.selectedOptionPresetID },
                        set: { viewModel.selectOptionPreset(id: $0) }
                    )
                ) {
                    ForEach(viewModel.optionPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    questionFocused = false
                    showingOptionEditor = true
                } label: {
                    Label(AppLanguage.text("編集", "Edit"), systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
        } label: {
            Label(AppLanguage.text("選択肢", "Options"), systemImage: "list.bullet")
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        GroupBox {
            if let result = viewModel.result {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.choice)
                            .font(.title2.bold())
                        Spacer()
                        Text(String(format: "%.0f ms", result.latencyMS))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.options, id: \.self) { option in
                        let p = result.probabilities[option] ?? 0
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(option)
                                    .font(.caption)
                                Spacer()
                                Text(p, format: .percent.precision(.fractionLength(1)))
                                    .font(.caption.monospacedDigit())
                            }
                            ProgressView(value: p)
                        }
                    }

                    Text(AppLanguage.text(
                        "候補内の相対スコアです。実際の正解確率として校正された値ではありません。",
                        "Scores are relative only to the supplied options and are not calibrated probabilities of correctness."
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(AppLanguage.text("まだ判定していません", "No result yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label(AppLanguage.text("判定", "Result"), systemImage: "bolt.circle")
        }
    }

    private var controlsCard: some View {
        GroupBox {
            VStack(spacing: 10) {
                Toggle(AppLanguage.text("連続判定", "Continuous"), isOn: Binding(
                    get: { viewModel.continuousEnabled },
                    set: { viewModel.setContinuous($0) }
                ))

                if viewModel.continuousEnabled {
                    Picker(AppLanguage.text("間隔", "Interval"), selection: $viewModel.continuousInterval) {
                        Text(AppLanguage.text("1秒", "1 sec")).tag(1.0)
                        Text(AppLanguage.text("2秒", "2 sec")).tag(2.0)
                        Text(AppLanguage.text("5秒", "5 sec")).tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    Text(AppLanguage.text(
                        "前の判定が終わるまで次の撮影は開始しません。キューは溜めません。",
                        "The next capture waits for the current decision to finish. Frames are not queued."
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if viewModel.selectedImage != nil {
                    Button {
                        Task { await viewModel.analyzeSelectedImage() }
                    } label: {
                        Label(AppLanguage.text("同じ画像でもう一度判定", "Analyze Same Image Again"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAnalyzing)
                }
            }
        } label: {
            Label(AppLanguage.text("動作", "Actions"), systemImage: "slider.horizontal.3")
        }
    }

    private var modelStatusText: String {
        switch viewModel.modelState {
        case .idle:
            AppLanguage.text(
                "初回のみ約1.8GBを取得。以後は端末内で判定",
                "Downloads about 1.8 GB once, then runs on-device"
            )
        case .loading(let progress):
            AppLanguage.text("準備中… \(Int(progress * 100))%", "Preparing… \(Int(progress * 100))%")
        case .ready:
            AppLanguage.text("準備完了 · 画像/質問は端末内推論", "Ready · image/question inference runs on-device")
        case .failed(let message):
            AppLanguage.text("失敗: \(message)", "Failed: \(message)")
        }
    }

    private var isModelLoading: Bool {
        if case .loading = viewModel.modelState { return true }
        return false
    }
}
