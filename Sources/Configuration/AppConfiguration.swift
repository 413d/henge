struct AppConfiguration: Codable, Equatable {
    var schemaVersion = 1
    var isEnabled = true
    var shortcut = Shortcut.defaultFixText
}
