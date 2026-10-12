import Testing
@testable import Henge

struct CasePreserverTests {
    @Test
    func preservesLowercaseCharacters() {
        let preserver = DefaultCasePreserver()

        #expect(preserver.preserveCase(original: "g", transformed: "п") == "п")
        #expect(preserver.preserveCase(original: "h", transformed: "р") == "р")
        #expect(preserver.preserveCase(original: "b", transformed: "и") == "и")
    }

    @Test
    func preservesUppercaseCharacters() {
        let preserver = DefaultCasePreserver()

        #expect(preserver.preserveCase(original: "G", transformed: "П") == "П")
        #expect(preserver.preserveCase(original: "H", transformed: "Р") == "Р")
        #expect(preserver.preserveCase(original: "T", transformed: "Е") == "Е")
    }

    @Test
    func leavesMixedCaseAndNonLetterResultsUntouched() {
        let preserver = DefaultCasePreserver()

        #expect(preserver.preserveCase(original: "g", transformed: "1") == "1")
        #expect(preserver.preserveCase(original: "G", transformed: "!" ) == "!")
        #expect(preserver.preserveCase(original: "_", transformed: "_") == "_")
    }
}
