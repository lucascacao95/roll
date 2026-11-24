import SwiftUI

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.10)))
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let symbol { Image(systemName: symbol).font(.system(size: 34, weight: .regular)).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 24, weight: .semibold))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConnectionBadge: View {
    let connected: Bool
    var body: some View {
        Label(connected ? L10n.text("Archive connected") : L10n.text("Archive unavailable"), systemImage: "circle.fill")
            .font(.callout.weight(.medium)).foregroundStyle(connected ? Color.green : Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background((connected ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
    }
}

struct LibraryCapacityView: View {
    @Environment(\.colorScheme) private var colorScheme
    let access: LibraryAccess
    private var foreground: Color { colorScheme == .dark ? RollBrand.ivory : RollBrand.charcoal }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(access.url?.lastPathComponent ?? L10n.text("Archive"), systemImage: "externaldrive")
                .font(.callout.weight(.medium)).foregroundStyle(foreground).lineLimit(2)
            if access.url != nil, let free = access.volume?.availableBytes {
                if let total = access.volume?.totalBytes, total > 0 {
                    ProgressView(value: Double(max(0, total - free)), total: Double(total)).tint(RollBrand.olive)
                    Text(L10n.text("%@ free of %@", String(describing: bytes(free)), String(describing: bytes(total)))).font(.caption).foregroundStyle(foreground.opacity(0.7))
                } else { Text(L10n.text("%@ free", String(describing: bytes(free)))).font(.caption).foregroundStyle(foreground.opacity(0.7)) }
                Text(L10n.text("Checked at connection")).font(.caption2).foregroundStyle(foreground.opacity(0.6))
            } else {
                Text(access.savedPath == nil ? L10n.text("Choose a destination folder") : L10n.text("Disconnected or inaccessible"))
                    .font(.caption).foregroundStyle(foreground.opacity(0.7))
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08)))
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}

struct InformationBanner: View {
    let title: String
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    if options[index].1 == selection { Label(options[index].0, systemImage: "checkmark") }
                    else { Text(options[index].0) }
                }
            }
        } label: {
            HStack {
                Text(options.first { $0.1 == selection }?.0 ?? title)
                Spacer(minLength: 10)
                Image(systemName: "chevron.down").foregroundStyle(.secondary)
            }.font(.body).padding(.horizontal, 12).padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.18)))
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(title)
    }
}
