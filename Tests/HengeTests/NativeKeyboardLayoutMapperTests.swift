import Testing
@testable import Henge

struct NativeKeyboardLayoutMapperTests {
    @Test
    func mapsBasicEnglishToRussianAlphabet() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("q", from: .english, to: .russian) == "й")
        #expect(mapper.map("w", from: .english, to: .russian) == "ц")
        #expect(mapper.map("e", from: .english, to: .russian) == "у")
        #expect(mapper.map("r", from: .english, to: .russian) == "к")
    }

    @Test
    func mapsBasicRussianToEnglishAlphabet() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("й", from: .russian, to: .english) == "q")
        #expect(mapper.map("ц", from: .russian, to: .english) == "w")
        #expect(mapper.map("у", from: .russian, to: .english) == "e")
    }

    @Test
    func mapsUppercasePreservingCase() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("Q", from: .english, to: .russian) == "Й")
        #expect(mapper.map("W", from: .english, to: .russian) == "Ц")
        #expect(mapper.map("Й", from: .russian, to: .english) == "Q")
    }

    @Test
    func mapsPunctuationAndBrackets() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("[", from: .english, to: .russian) == "х")
        #expect(mapper.map("]", from: .english, to: .russian) == "ъ")
        #expect(mapper.map(";", from: .english, to: .russian) == "ж")
        #expect(mapper.map("'", from: .english, to: .russian) == "э")
        #expect(mapper.map(",", from: .english, to: .russian) == "б")
        #expect(mapper.map(".", from: .english, to: .russian) == "ю")
    }

    @Test
    func mapsFullStrings() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map(text: "ghbdtn", from: .english, to: .russian) == "привет")
        #expect(mapper.map(text: "ghbdtn, vbh!", from: .english, to: .russian) == "привет, мир!")
        #expect(mapper.map(text: "ghbdtn_123", from: .english, to: .russian) == "привет_123")
        #expect(mapper.map(text: "привет", from: .russian, to: .english) == "ghbdtn")
    }

    @Test
    func preservesUnmappedCharacters() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("1", from: .english, to: .russian) == "1")
        #expect(mapper.map(" ", from: .english, to: .russian) == " ")
        #expect(mapper.map("🎉", from: .english, to: .russian) == nil)
    }

    @Test
    func fallsBackToBundledAnsiTableWhenSystemLayoutDataIsUnavailable() {
        let mapper = NativeKeyboardLayoutMapper(layoutData: [:])
        #expect(mapper.map("q", from: .english, to: .russian) == "й")
        #expect(mapper.map("Q", from: .english, to: .russian) == "Й")
        #expect(mapper.map("[", from: .english, to: .russian) == "х")
        #expect(mapper.map("й", from: .russian, to: .english) == "q")
        #expect(mapper.map(text: "ghbdtn, vbh!", from: .english, to: .russian) == "привет, мир!")
    }
}
