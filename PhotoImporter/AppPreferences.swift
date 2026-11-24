import Foundation
import Observation

struct FolderOrganization: Codable, Equatable, Hashable, Sendable {
    var yearFolder = true
    var formatFolders = true

    var description: String {
        (yearFolder ? L10n.text("Year / ") : "") + L10n.text("date - event / ") + (formatFolders ? L10n.text("RAW or JPEG / ") : "") + L10n.text("original filename")
    }
}

@MainActor @Observable
final class AppPreferences {
    static let shared = AppPreferences()
    @ObservationIgnored private let defaults: UserDefaults
    var format: PhotoFormatFilter { didSet { defaults.set(format.rawValue, forKey: "defaultFormat") } }
    var onlyNotImported: Bool { didSet { defaults.set(onlyNotImported, forKey: "defaultOnlyNotImported") } }
    var organization: FolderOrganization { didSet {
        if let data = try? JSONEncoder().encode(organization) { defaults.set(data, forKey: "organization") }
    } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        format = defaults.string(forKey: "defaultFormat").flatMap(PhotoFormatFilter.init(rawValue:)) ?? .all
        onlyNotImported = defaults.bool(forKey: "defaultOnlyNotImported")
        organization = defaults.data(forKey: "organization").flatMap { try? JSONDecoder().decode(FolderOrganization.self, from: $0) } ?? FolderOrganization()
    }

    var filters: PhotoFilters { PhotoFilters(format: format, onlyNotImported: onlyNotImported) }
}
