import SwiftUI

struct ImportOperationView: View {
    @Bindable var model: DiscoveryModel

    var body: some View {
        if model.isImporting {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: model.importProgress?.fraction ?? 0)
                if let progress = model.importProgress {
                    Text("\(progress.phase): \(progress.path)").font(.callout)
                    Text(L10n.text("%@ of %@ files complete", String(describing: progress.completedFiles), String(describing: progress.totalFiles)))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("Revalidating the source, archive and local record…"))
                }
            }
            Spacer()
        }
        if let error = model.importError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
        if let report = model.importReport {
            Text(report.title).font(.headline)
            Text(L10n.text("%@ copied · %@ already present and verified · %@ failed", String(describing: report.copiedCount), String(describing: report.existingCount), String(describing: report.failedCount)))
                .font(.callout)
            if let error = report.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Table(report.files) {
                TableColumn(L10n.text("Source"), value: \.sourceRelativePath)
                TableColumn(L10n.text("Destination"), value: \.destinationRelativePath)
                TableColumn(L10n.text("Result")) { file in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.status.label)
                        if let error = file.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                    }.help(file.error ?? file.sha256.map { "SHA-256: " + $0 } ?? file.status.label)
                }
            }
            Text(L10n.text("Local record: %@. Files that were not started remain identified in the summary.", String(describing: report.id.uuidString)))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
