import SwiftUI

/// AI 歌单的选择流程。问题会根据前一步选择调整，最后一项始终为自定义。
struct AIPlaylistComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let onGenerate: (AIPlaylistPreferences) -> Void

    @State private var mood = "温柔治愈"
    @State private var scene = "夜晚独处"
    @State private var energy = "缓慢铺陈"
    @State private var language = "不限语言"
    @State private var trackCountChoice = "12 首"
    @State private var customTrackCount = 12
    @State private var customDirection = ""

    private var needsCustomDirection: Bool {
        [mood, scene, energy, language].contains("自定义")
    }

    private var selectedTrackCount: Int {
        trackCountChoice == "自定义" ? customTrackCount : Int(trackCountChoice.replacingOccurrences(of: " 首", with: "")) ?? 12
    }

    private var sceneOptions: [String] {
        switch mood {
        case "电子律动": return ["通勤路上", "运动时刻", "夜间派对", "自定义"]
        case "失恋释怀": return ["夜晚独处", "雨天发呆", "散步回家", "自定义"]
        case "热血向前": return ["工作专注", "出门远行", "运动时刻", "自定义"]
        default: return ["夜晚独处", "阅读写字", "雨天发呆", "自定义"]
        }
    }

    private var energyOptions: [String] {
        scene == "运动时刻" ? ["稳定推进", "热烈爆发", "轻快跳跃", "自定义"] : ["缓慢铺陈", "轻快明亮", "情绪递进", "自定义"]
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

                        choiceGroup("这一刻想要什么情绪？", options: ["温柔治愈", "失恋释怀", "电子律动", "热血向前", "自定义"], selection: $mood)
                        choiceGroup("准备在什么场景听？", options: sceneOptions, selection: $scene)
                        choiceGroup("希望歌单的能量如何？", options: energyOptions, selection: $energy)
                        choiceGroup("语言怎么选？", options: ["不限语言", "华语优先", "英语优先", "韩语/日语优先", "自定义"], selection: $language)
                        choiceGroup("想生成多少首歌？", options: ["8 首", "12 首", "16 首", "20 首", "自定义"], selection: $trackCountChoice)

                        if trackCountChoice == "自定义" {
                            HStack {
                                Text("自定义歌曲数量").font(.headline)
                                Spacer()
                                Stepper("\(customTrackCount) 首", value: $customTrackCount, in: 6...30)
                                    .labelsHidden()
                                Text("\(customTrackCount) 首").font(.subheadline.weight(.semibold))
                            }
                            .padding(15)
                            .appGlass(cornerRadius: 18)
                        }

                        if needsCustomDirection {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("自定义方向")
                                    .font(.headline)
                                TextField("例如：适合凌晨开车，女声为主", text: $customDirection, axis: .vertical)
                                    .lineLimit(2...4)
                                    .padding(12)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .padding(15)
                            .appGlass(cornerRadius: 18)
                        }

                        Button {
                            let preferences = AIPlaylistPreferences(
                                mood: mood,
                                scene: scene,
                                energy: energy,
                                language: language,
                                trackCount: selectedTrackCount,
                                customDirection: needsCustomDirection ? customDirection.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                            )
                            dismiss()
                            onGenerate(preferences)
                        } label: {
                            Label("让 AI 深度创建歌单", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppPalette.violet)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .navigationTitle("AI 歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }

    private func choiceGroup(_ title: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(options, id: \.self) { option in
                    Button { selection.wrappedValue = option } label: {
                        Text(option)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(selection.wrappedValue == option ? Color.white : Color.primary)
                            .background(selection.wrappedValue == option ? AppPalette.violet : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(15)
        .appGlass(cornerRadius: 20)
    }
}

struct AIPlaylistGenerationView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let playlist: LocalAIPlaylist?

    private var manager: RecommendationManager { app.recommendationManager }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(manager.playlistGenerationStatus ?? "正在准备…", systemImage: manager.isCreatingPlaylist ? "brain.head.profile" : "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(manager.isCreatingPlaylist ? AppPalette.violet : .green)

                            streamCard(title: "AI 深度思考", text: manager.playlistThinking.isEmpty ? "正在分析你的选择…" : manager.playlistThinking, icon: "brain")
                            streamCard(title: "AI 歌单方案", text: manager.playlistOutput.isEmpty ? "正在组织歌单…" : manager.playlistOutput, icon: "text.quote")

                            if let playlist {
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
                    .onChange(of: manager.playlistThinking) { _, _ in proxy.scrollTo("stream-end", anchor: .bottom) }
                    .onChange(of: manager.playlistOutput) { _, _ in proxy.scrollTo("stream-end", anchor: .bottom) }
                }
            }
            .navigationTitle("AI 正在创作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .disabled(manager.isCreatingPlaylist)
                }
            }
        }
        .interactiveDismissDisabled(manager.isCreatingPlaylist)
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
