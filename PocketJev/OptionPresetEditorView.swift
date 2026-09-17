import SwiftUI

struct OptionPresetEditorView: View {
    @Bindable var viewModel: DecisionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingPreset: OptionPreset?

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.optionPresets) { preset in
                    Button {
                        editingPreset = preset
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name)
                                .foregroundStyle(.primary)
                            Text(preset.options.joined(separator: " / "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: viewModel.deleteOptionPresets)
            }
            .navigationTitle(AppLanguage.text("選択肢を編集", "Edit Options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.text("閉じる", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingPreset = OptionPreset(
                            id: UUID().uuidString,
                            name: AppLanguage.text("新しい選択肢", "New Option Set"),
                            options: ["YES", "NO", AppLanguage.text("判別不能", "UNKNOWN")]
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingPreset) { preset in
                OptionPresetFormView(viewModel: viewModel, preset: preset)
            }
        }
    }
}

private struct OptionPresetFormView: View {
    @Bindable var viewModel: DecisionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OptionPreset
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case option(Int)
    }

    init(viewModel: DecisionViewModel, preset: OptionPreset) {
        self.viewModel = viewModel
        _draft = State(initialValue: preset)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLanguage.text("名前", "Name")) {
                    TextField(
                        AppLanguage.text("例: YES / NO / 判別不能", "e.g. YES / NO / UNKNOWN"),
                        text: $draft.name
                    )
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                Section(AppLanguage.text("選択肢", "Options")) {
                    ForEach(Array(draft.options.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            Text(String(UnicodeScalar(65 + index)!))
                                .font(.caption.monospaced().bold())
                                .frame(width: 22, height: 22)
                                .background(.secondary.opacity(0.18), in: Circle())

                            TextField(
                                AppLanguage.text("選択肢", "Option"),
                                text: Binding(
                                    get: { draft.options[index] },
                                    set: { draft.options[index] = $0 }
                                )
                            )
                            .focused($focusedField, equals: .option(index))
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }

                            if draft.options.count > 2 {
                                Button(role: .destructive) {
                                    draft.options.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                        }
                    }

                    if draft.options.count < 26 {
                        Button {
                            draft.options.append(
                                AppLanguage.text("選択肢\(draft.options.count + 1)", "Option \(draft.options.count + 1)")
                            )
                        } label: {
                            Label(AppLanguage.text("追加", "Add"), systemImage: "plus.circle")
                        }
                    }
                }

                if !validationMessage.isEmpty {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppLanguage.text("選択肢セット", "Option Set"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.text("キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.text("保存", "Save")) {
                        focusedField = nil
                        viewModel.upsertOptionPreset(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppLanguage.text("完了", "Done")) { focusedField = nil }
                }
            }
        }
    }

    private var cleanedOptions: [String] {
        draft.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (2...26).contains(cleanedOptions.count)
            && cleanedOptions.allSatisfy { !$0.isEmpty }
            && Set(cleanedOptions).count == cleanedOptions.count
    }

    private var validationMessage: String {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppLanguage.text("名前を入力してください。", "Enter a name.")
        }
        if cleanedOptions.contains(where: { $0.isEmpty }) {
            return AppLanguage.text("空の選択肢は保存できません。", "Empty options cannot be saved.")
        }
        if Set(cleanedOptions).count != cleanedOptions.count {
            return AppLanguage.text("同じ選択肢を重複して登録できません。", "Duplicate options are not allowed.")
        }
        return ""
    }
}
