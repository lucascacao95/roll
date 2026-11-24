import Foundation

/// English catalog keys with pt-BR translations. Persisted enum raw values stay unchanged.
enum L10n {
    static func text(_ key: String, _ arguments: String...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func legacyLabel(_ value: String) -> String {
        text(legacyLabels[value] ?? value)
    }

    private static let legacyLabels: [String: String] = [
        "Todos (RAW e JPEG)": "RAW + JPEG",
        "Preferências": "Settings",
        "Importar": "New Roll",
        "Histórico": "History",
        "Íntegro — SHA-256 conferido": "Intact — SHA-256 verified",
        "Ausente no destino": "Missing at destination",
        "Conteúdo diferente": "Different content",
        "Sem checksum de referência": "No reference checksum",
        "Não foi possível verificar": "Could not verify",
        "Todos": "All",
        "Concluídas": "Completed",
        "Interrompidas": "Interrupted",
        "Parciais": "Partial",
        "Com erros": "With Errors",
        "Canceladas": "Cancelled Rolls",
        "Ativas": "Active"
    ]
}
