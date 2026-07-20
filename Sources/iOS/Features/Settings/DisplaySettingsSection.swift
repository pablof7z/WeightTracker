import SwiftUI
import PhotosUI
import UIKit

struct DisplaySettingsSection: View {
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.theme) private var themeRaw: String = ThemePreference.system.rawValue
    @AppStorage(AppPrefKey.todayLensOrder) private var lensOrderRaw: String = ""
    @AppStorage(AppPrefKey.todayLensHidden) private var lensHiddenRaw: String = ""

    /// Working copy of the order so drag-reorder is smooth; every mutation is
    /// written straight back through `TodayLensOrder`.
    @State private var lensOrder = TodayLensOrder.default
    @ObservedObject private var photoStore = DailyPhotoStore.shared
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        Section {
            Picker("Weight unit", selection: $weightUnitRaw) {
                ForEach(WeightUnit.allCases, id: \.rawValue) { u in
                    Text(u.label).tag(u.rawValue)
                }
            }
            Picker("Body unit", selection: $bodyUnitRaw) {
                ForEach(BodyUnit.allCases, id: \.rawValue) { u in
                    Text(u.label).tag(u.rawValue)
                }
            }
            Picker("Theme", selection: $themeRaw) {
                ForEach(ThemePreference.allCases, id: \.rawValue) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Weight and body units apply throughout the app. Theme overrides the system appearance for this app only.")
        }

        Section {
            ForEach(lensOrder) { lens in
                HStack(spacing: 12) {
                    LensSwatch(lens: lens)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(lens.label)
                            .font(.subheadline.weight(.medium))
                        Text(lens.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: binding(for: lens))
                        .labelsHidden()
                        .accessibilityLabel("Show \(lens.label)")
                }
                .padding(.vertical, 3)
            }
            .onMove { offsets, destination in
                lensOrder.move(fromOffsets: offsets, toOffset: destination)
                lensOrderRaw = TodayLensOrder.encode(lensOrder)
            }
        } header: {
            Text("Today charts")
        } footer: {
            Text("Tap Edit to arrange the swipe order. Switch off any chart you don't want in the carousel. Today always opens on Current weight when it is on. Turning everything off falls back to Current weight.")
        }
        .onAppear {
            lensOrder = TodayLensOrder.decode(lensOrderRaw)
        }

        Section {
            Toggle("Use my photos", isOn: $photoStore.enabled)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 12,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(photoStore.count == 0 ? "Choose photos" : "Add more photos",
                      systemImage: "photo.on.rectangle.angled")
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            photoStore.addImageData(data)
                        }
                    }
                    pickerItems = []
                }
            }

            if photoStore.count > 0 {
                LabeledContent("Selected", value: "\(photoStore.count) photo\(photoStore.count == 1 ? "" : "s")")

                PhotoBackdropGrid(photoStore: photoStore)

                Button(role: .destructive) {
                    photoStore.removeAll()
                } label: {
                    Text("Remove all photos")
                }
            }
        } header: {
            Text("Today backdrop")
        } footer: {
            Text("Optional. One of your photos is chosen per day and shown behind the Today canvas, tinted to the active lens. When off, an atmospheric gradient is used.")
        }
    }

    /// Per-lens visibility, stored as the hidden set so a lens added in a future
    /// release is visible by default rather than silently missing.
    private func binding(for lens: TodayLens) -> Binding<Bool> {
        Binding(
            get: { !TodayLensOrder.decodeHidden(lensHiddenRaw).contains(lens) },
            set: { shown in
                var hidden = TodayLensOrder.decodeHidden(lensHiddenRaw)
                if shown { hidden.remove(lens) } else { hidden.insert(lens) }
                lensHiddenRaw = TodayLensOrder.encodeHidden(hidden)
            }
        )
    }
}

/// Tiny accent-tinted thumbnail hinting at each lens's form — a line, a line
/// with range whiskers, or bars — so the list is scannable without prose.
private struct LensSwatch: View {
    let lens: TodayLens

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(lens.accent.opacity(0.16))

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    if lens == .weeklyLoss {
                        Path { p in
                            p.addRect(CGRect(x: w * 0.14, y: h * 0.44, width: 6, height: h * 0.30))
                            p.addRect(CGRect(x: w * 0.42, y: h * 0.28, width: 6, height: h * 0.46))
                            p.addRect(CGRect(x: w * 0.70, y: h * 0.52, width: 6, height: h * 0.22))
                        }
                        .fill(lens.accent.opacity(0.85))
                    } else {
                        if lens == .weeklyRange {
                            Path { p in
                                for x in [w * 0.18, w * 0.46, w * 0.74] {
                                    p.move(to: CGPoint(x: x, y: h * 0.22))
                                    p.addLine(to: CGPoint(x: x, y: h * 0.78))
                                }
                            }
                            .stroke(lens.accent.opacity(0.45), lineWidth: 1)
                        }
                        Path { p in
                            p.move(to: CGPoint(x: 5, y: h * 0.30))
                            p.addCurve(
                                to: CGPoint(x: w - 5, y: h * 0.70),
                                control1: CGPoint(x: w * 0.34, y: h * 0.36),
                                control2: CGPoint(x: w * 0.58, y: h * 0.64)
                            )
                        }
                        .stroke(lens.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                    }
                }
            }
        }
        .frame(width: 44, height: 30)
        .accessibilityHidden(true)
    }
}

/// Thumbnail grid of the stored backdrop photos with a per-photo remove
/// affordance, so a single unwanted photo can be dropped without wiping
/// the whole collection via "Remove all photos".
private struct PhotoBackdropGrid: View {
    @ObservedObject var photoStore: DailyPhotoStore

    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 80), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(photoStore.filenames, id: \.self) { name in
                PhotoBackdropThumbnail(photoStore: photoStore, name: name)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PhotoBackdropThumbnail: View {
    @ObservedObject var photoStore: DailyPhotoStore
    let name: String

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                photoStore.remove(name)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove photo")
        }
        .task {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> UIImage? {
        let url = photoStore.url(for: name)
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}
