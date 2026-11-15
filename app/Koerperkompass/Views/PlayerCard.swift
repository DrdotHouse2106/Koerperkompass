import PhotosUI
import SwiftUI

/// Spielerkarte zum Teilen: eigenes Foto, Name, Klasse, Rang, Level und Serie.
/// Das Foto wird nur lokal auf dem iPhone gespeichert.
struct PlayerCardView: View {
    let progress: QuestProgress
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var avatar = Avatar.load()
    @State private var pick: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                let card = PlayerCard(progress: progress, name: state.profile.name ?? "", avatar: avatar)
                card
                HStack {
                    PhotosPicker("Foto wählen", selection: $pick, matching: .images).buttonStyle(.bordered)
                    if let image = render(card) {
                        ShareLink(item: image, preview: SharePreview("Spielerkarte", image: image)) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    }
                }
            }
            .padding()
            .navigationTitle("Spielerkarte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fertig") { dismiss() } }
            .onChange(of: pick) {
                Task {
                    if let data = try? await pick?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        Avatar.save(img)
                        avatar = Avatar.load()
                    }
                }
            }
        }
    }

    private func render(_ card: PlayerCard) -> Image? {
        let r = ImageRenderer(content: card.frame(width: 320).padding())
        r.scale = 3
        return r.uiImage.map { Image(uiImage: $0) }
    }
}

struct PlayerCard: View {
    let progress: QuestProgress
    let name: String
    let avatar: UIImage?

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [.orange, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "safari.fill").font(.system(size: 90)).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .frame(height: 300)
                .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    if !name.isEmpty { Text(name).font(.title2.bold()) }
                    Text(progress.characterClass).font(.subheadline.bold()).foregroundStyle(.orange)
                }
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.linearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))

            HStack(spacing: 10) {
                box("Rang", Text(progress.rank))
                box("Level", Text("\(progress.level)"))
                box("Serie", Text("🔥 \(progress.streak)"))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.linearGradient(colors: [.orange, .teal], startPoint: .top, endPoint: .bottom), lineWidth: 3))
    }

    private func box(_ title: LocalizedStringResource, _ value: Text) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary).textCase(.uppercase)
            value.font(.headline).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Avatar als Datei im App-Ordner (wird nicht synchronisiert)
enum Avatar {
    static let url = URL.documentsDirectory.appendingPathComponent("avatar.jpg")
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
    static func save(_ image: UIImage) { try? image.jpeg(maxSide: 800, quality: 0.8)?.write(to: url) }
}
