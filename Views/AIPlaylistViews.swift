import SwiftUI

/// AI 通过 present_choice 工具逐轮驱动的可点击选择器。
struct AIPlaylistComposerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let onGenerate: (AIPlaylistPreferences) -> Void

    @State private var trackCountChoice = "12 首"
    @State private var customTrackCount = 12
    @State private var selectedOption: String?
    @State private var customAnswer = ""

    private var manager: RecommendationManager { app.recommendationManager }

    private var selectedTrackCount: Int {
        trackCountChoice == "自定义" ? customTrackCount : Int(trackCountChoice.replacingOccurrences(of: " 首", with: "")) ?? 12
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("创建本地 AI 歌单", systemImage: "sparkles")
                                .font(.title2.bold())
                                .foregroundStyle(AppPalette.violet)
                            Text("不上传、不写入网易云；AI 会依据你的选择深度策展。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        answerHistory
                        selectorContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .navigationTitle("AI 歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重新开始") { Task { await manager.resetPlaylistChoiceInterview() } }
                        .disabled(manager.isLoadingPlaylistChoice)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } }
            }
            .task { await manager.beginPlaylistChoiceInterview() }
        }
    }

    @ViewBuilder
    private var answerHistory: some View {
        if !manager.playlistChoiceAnswers.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(manager.playlistChoiceAnswers) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.question).font(.caption).foregroundStyle(.secondary)
                        Text(item.answer).font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .appGlass(cornerRadius: 18)
        }
    }

    @ViewBuilder
    private var selectorContent: some View {
        if manager.isLoadingPlaylistChoice {
            VStack(spacing: 12) {
                ProgressView()
                Text("AI 正在决定下一道选择题…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else if let error = manager.playlistChoiceError {
            VStack(alignment: .leading, spacing: 12) {
                Label("选择器加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.red)
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("重试") { Task { await manager.beginPlaylistChoiceInterview() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .appGlass(cornerRadius: 20)
        } else if manager.isPlaylistInterviewReady {
            finalCreationControls
        } else if let question = manager.playlistChoiceQuestion {
            VStack(alignment: .leading, spacing: 13) {
                Label("AI 想问你", systemImage: "questionmark.bubble.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(AppPalette.violet)
                Text(question.question).font(.title3.bold())
                VStack(spacing: 9) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            selectedOption = option
                            if option != "自定义" {
                                selectedOption = nil
                                customAnswer = ""
                                Task { await manager.submitPlaylistChoice(option) }
                            }
                        } label: {
                            HStack {
                                Text(option).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if selectedOption == "自定义" {
                    TextField("输入你的自定义选择", text: $customAnswer, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button("提交自定义选择") {
                        let value = customAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        selectedOption = nil
                        customAnswer = ""
                        Task { await manager.submitPlaylistChoice(value) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.violet)
                    .disabled(customAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .appGlass(cornerRadius: 22)
        }
    }

    private var finalCreationControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI 已了解你的方向", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            Text("最后选择歌单歌曲数量")
                .font(.subheadline).foregroundStyle(.secondary)
            choiceGroup("想生成多少首歌？", options: ["8 首", "12 首", "16 首", "20 首", "自定义"], selection: $trackCountChoice)
            if trackCountChoice == "自定义" {
                Stepper("\(customTrackCount) 首", value: $customTrackCount, in: 6...30)
                    .padding(12)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button {
                let preferences = manager.playlistPreferences(trackCount: selectedTrackCount)
                dismiss()
                onGenerate(preferences)
            } label: {
                Label("让 V4 Pro 深度创建", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.violet)
        }
        .padding(16)
        .appGlass(cornerRadius: 22)
    }

    private func choiceGroup(_ title: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(options, id: \.self) { option in
                    Button { selection.wrappedValue = option } label: {
                        Text(option).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(selection.wrappedValue == option ? Color.white : Color.primary)
                            .background(selection.wrappedValue == option ? AppPalette.violet : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct AIPlaylistGenerationView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var autoScrollTask: Task<Void, Never>?

    private var manager: RecommendationManager { app.recommendationManager }

    private var statusIcon: String {
        if manager.isCreatingPlaylist { return "brain.head.profile" }
        if manager.playlistGenerationError != nil { return "exclamationmark.triangle.fill" }
        return "checkmark.seal.fill"
    }

    private var statusColor: Color {
        if manager.isCreatingPlaylist { return AppPalette.violet }
        if manager.playlistGenerationError != nil { return .red }
        return .green
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(manager.playlistGenerationStatus ?? "正在准备…", systemImage: statusIcon)
                                .font(.headline)
                                .foregroundStyle(statusColor)

                            streamCard(title: "AI 深度思考", text: manager.playlistThinking.isEmpty ? "正在分析你的选择…" : manager.playlistThinking, icon: "brain")
                            streamCard(title: "AI 歌单方案", text: manager.playlistOutput.isEmpty ? "正在组织歌单…" : manager.playlistOutput, icon: "text.quote")

                            if let error = manager.playlistGenerationError {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("创建失败", systemImage: "exclamationmark.triangle.fill")
                                        .font(.headline)
                                        .foregroundStyle(.red)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .appGlass(cornerRadius: 20)
                            }

                            if let playlist = manager.lastCreatedPlaylist {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(playlist.title).font(.title3.bold())
                                    Text(playlist.summary).font(.subheadline).foregroundStyle(.secondary)
                                    Text("已在本机创建 \(playlist.songs.count) 首歌曲，未同步到网易云。")
                                        .font(.caption).foregroundStyle(AppPalette.violet)
                                }
                                .padding(16)
                                .appGlass(cornerRadius: 20)
                            }
                            Color.clear.frame(height: 1).id("stream-end")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .onChange(of: manager.playlistThinking.count + manager.playlistOutput.count) { _, _ in
                        scheduleAutoScroll(using: proxy)
                    }
                }
            }
            .navigationTitle(manager.isCreatingPlaylist ? "AI 正在创作" : "AI 歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .disabled(manager.isCreatingPlaylist)
                }
            }
        }
        .interactiveDismissDisabled(manager.isCreatingPlaylist)
        .onDisappear {
            autoScrollTask?.cancel()
            autoScrollTask = nil
        }
    }

    private func scheduleAutoScroll(using proxy: ScrollViewProxy) {
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            proxy.scrollTo("stream-end", anchor: .bottom)
            autoScrollTask = nil
        }
    }

    private func streamCard(title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .appGlass(cornerRadius: 20)
    }
}

struct LocalAIPlaylistDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let playlist: LocalAIPlaylist

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("本地 AI 歌单", systemImage: "sparkles")
                            .font(.caption.weight(.bold)).foregroundStyle(AppPalette.violet)
                        Text(playlist.title).font(.title2.bold())
                        Text(playlist.summary).font(.subheadline).foregroundStyle(.secondary)
                        Text("仅保存在此 App，不会同步网易云音乐")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
                    .appGlass(cornerRadius: 22)

                    if !playlist.thoughts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI 创作想法").font(.headline)
                            ForEach(playlist.thoughts, id: \.self) { thought in
                                Label(thought, systemImage: "sparkle")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .appGlass(cornerRadius: 20)
                    }

                    ForEach(playlist.songs) { SongCard(song: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("AI 歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
