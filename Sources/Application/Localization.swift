import Foundation

enum L10n {
    static func string(
        _ key: String,
        defaultValue: String,
        bundle: Bundle = .main
    ) -> String {
        bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    static func format(
        _ key: String,
        defaultValue: String,
        bundle: Bundle = .main,
        _ arguments: CVarArg...
    ) -> String {
        let template = string(key, defaultValue: defaultValue, bundle: bundle)
        return String(format: template, arguments: arguments)
    }
}
