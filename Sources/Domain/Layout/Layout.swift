/// Identifies one of the two keyboard layouts Henge translates between.
///
/// The layout is a domain concept only; resolving it to a concrete system
/// input source is an infrastructure concern.
public enum Layout: String, CaseIterable, Codable, Sendable {
    case english
    case russian
}
