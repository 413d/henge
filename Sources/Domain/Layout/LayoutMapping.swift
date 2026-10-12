/// Translates characters between keyboard layouts.
///
/// Implementations resolve the physical key that produces a character under
/// `source` and report the character the same key produces under `target`,
/// which is why the mapping is layout-driven rather than a transliteration.
public protocol LayoutMapping: Sendable {
    /// Returns the character produced under `target` by the key that produces
    /// `character` under `source`, or `nil` when no such mapping exists.
    func map(_ character: Character, from source: Layout, to target: Layout) -> Character?

    /// Translates `text` character by character, leaving characters without a
    /// mapping untouched.
    ///
    /// Implementations are expected to preserve the input character count so
    /// domain-level case preservation can be applied positionally.
    func map(text: String, from source: Layout, to target: Layout) -> String
}
