import SwiftUI

// 用户反馈表单 sheet — 在 Settings 底部入口拉起.
// 写完 Submit → 入 FeedbackStore 队列 + 立刻试 send → dismiss + 提示.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var feedbackStore = FeedbackStore.shared
    @FocusState private var focused: Bool
    /// 提交后给个轻量 inline 状态 — 网络结果回来再更新
    @State private var status: SubmitStatus = .idle

    private enum SubmitStatus {
        case idle, submitting, submitted
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // header 提示
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tell us what's broken, missing, or worth changing.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                    Text("Your feedback gets bundled into a daily digest and emailed to the team. No account, no tracking.")
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textDim)
                }
                .padding(.top, 8)

                // 输入区
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type your feedback here…")
                            .font(.system(size: 15))
                            .foregroundStyle(MasoColor.textFaint)
                            .padding(.top, 12)
                            .padding(.leading, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 15))
                        .foregroundStyle(MasoColor.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .focused($focused)
                }
                .frame(minHeight: 160, maxHeight: 280, alignment: .topLeading)
                .background(MasoColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))

                // pending count — 让用户知道队列状态
                if feedbackStore.pending.count > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(feedbackStore.pending.count) item\(feedbackStore.pending.count > 1 ? "s" : "") queued · digest sends within 24h")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(MasoColor.textDim)
                }

                Spacer()

                // 提交按钮
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if status == .submitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        }
                        Text(status == .submitted ? "Sent — thank you" : "Submit feedback")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? MasoColor.accent : MasoColor.surfaceHi)
                    .foregroundStyle(canSubmit ? .black : MasoColor.textDim)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.bottom, 20)
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .frame(width: 30, height: 30)
                            .background(MasoColor.surfaceHi)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            .onAppear { focused = true }
        }
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        status != .submitting
    }

    private func submit() {
        guard canSubmit else { return }
        let body = text
        status = .submitting
        feedbackStore.submit(body)
        // 给个短暂"sent"反馈, 然后 dismiss.
        // 实际发送是 fire-and-forget, 失败也保留在 pending 下次再试.
        Task {
            // 等 1.2s 让用户看到 "Sent — thank you" 状态
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                status = .submitted
                // 再 0.5s dismiss
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

#Preview {
    FeedbackSheet()
        .preferredColorScheme(.dark)
}
