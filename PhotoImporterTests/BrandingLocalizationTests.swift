import XCTest
@testable import PhotoImporter

@MainActor
final class BrandingLocalizationTests: XCTestCase {
    func testRuntimeLanguageAndPathArguments() {
        let portuguese = Bundle.main.preferredLocalizations.first?.hasPrefix("pt") == true
        XCTAssertEqual(L10n.text("New Roll"), portuguese ? "Novo rolo" : "New Roll")
        XCTAssertEqual(L10n.text("Archive"), portuguese ? "Acervo" : "Archive")
        let path = "/DCIM/100%/P100001.JPG"
        XCTAssertEqual(L10n.text("Source unavailable: %@", path),
                       (portuguese ? "Origem indisponível: " : "Source unavailable: ") + path)
    }

    func testEnglishAndBrazilianPortugueseCatalogsKeepMatchingArguments() throws {
        let english = try strings("en")
        let portuguese = try strings("pt-BR")
        XCTAssertGreaterThan(english.count, 300)
        XCTAssertEqual(Set(english.keys), Set(portuguese.keys))
        for key in english.keys {
            let source = try XCTUnwrap(english[key])
            let translation = try XCTUnwrap(portuguese[key])
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertEqual(source.components(separatedBy: "%@").count,
                           translation.components(separatedBy: "%@").count, key)
        }
        XCTAssertEqual(english["New Roll"], "New Roll")
        XCTAssertEqual(portuguese["New Roll"], "Novo rolo")
        XCTAssertEqual(portuguese["Settings"], "Ajustes")
        XCTAssertEqual(portuguese["Archive"], "Acervo")
        let template = try XCTUnwrap(portuguese["%@ photos found"])
        XCTAssertEqual(String(format: template, "350"), "350 fotografias encontradas")
    }

    func testProductRenamePreservesApplicationAndStorageIdentity() throws {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.bundleIdentifier, "local.lucas.PhotoImporter")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Roll")
        XCTAssertEqual(bundle.executableURL?.lastPathComponent, "Roll")
        XCTAssertEqual(bundle.bundleURL.lastPathComponent, "Roll.app")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String, "en")
        XCTAssertTrue(ImportJournal.defaultRoot.path.hasSuffix("PhotoImporter/Imports"))
        // Previously saved format preferences remain readable under the same raw values.
        XCTAssertEqual(PhotoFormatFilter.all.rawValue, "Todos (RAW e JPEG)")
        XCTAssertEqual(PhotoFormatFilter(rawValue: "Todos (RAW e JPEG)"), .all)
        XCTAssertEqual(PhotoFormatFilter(rawValue: "JPEG"), .jpeg)
    }

    func testSafetyAndRecoveryMessagesExistInBothLanguages() throws {
        for language in ["en", "pt-BR"] {
            let catalog = try strings(language)
            for key in [
                "Existing files are never overwritten",
                "SHA-256 verification is required after copying",
                "The source changed during copying. The final file was not published.",
                "Confirm Archive…", "Prepare Recovery", "Inspect Temporary Files"
            ] {
                XCTAssertNotNil(catalog[key], "\(language): \(key)")
            }
        }
    }

    private func strings(_ localization: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                               subdirectory: nil, localization: localization))
        let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(value as? [String: String])
    }
}
