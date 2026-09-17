import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro(
                        title: "PocketJev",
                        subtitle: AppLanguage.text(
                            "端末内で動く、画像の少数択判定ツール",
                            "A small on-device visual decision tool."
                        ),
                        body: AppLanguage.text(
                            "カメラや写真をQwen3-VLで確認し、長い説明文を生成せず、指定した選択肢の中から判定します。モデルは初回取得後、iPhone内で動作します。",
                            "PocketJev uses Qwen3-VL on your iPhone to inspect a camera image or photo and choose among the options you provide. It is designed for quick classification rather than generating a long description. After the model is downloaded once, inference runs on-device."
                        )
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLanguage.text("使い方", "How to use"))
                            .font(.headline)
                        Text(AppLanguage.text(
                            "1. 初回だけAIモデルを準備します。\n2. 質問を入力します。\n3. YES / NO / 判別不能などの選択肢セットを選びます。\n4. 撮影するか写真を選びます。\n5. PocketJevが判定結果と相対スコアを表示します。",
                            "1. Prepare the AI model once.\n2. Enter a question.\n3. Choose an option set such as YES / NO / UNKNOWN.\n4. Take a photo or select one from Photos.\n5. PocketJev shows the selected answer and relative score."
                        ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(AppLanguage.text(
                        "表示される割合は、指定した選択肢の中での相対スコアです。実際の正解確率として校正された値ではありません。",
                        "The displayed percentages are relative scores among the supplied choices. They are not calibrated probabilities of correctness."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle(AppLanguage.text("PocketJevについて", "About PocketJev"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.text("閉じる", "Done")) { dismiss() }
                }
            }
        }
    }

    private func intro(title: String, subtitle: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
