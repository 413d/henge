import Foundation
import Testing

struct ProjectFileIntegrityTests {
    private static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HengeTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }()

    private static var pbxprojURL: URL {
        repositoryRoot.appendingPathComponent("Henge.xcodeproj/project.pbxproj")
    }

    @Test
    func projectObjectIDsAreUnique() throws {
        let content = try String(contentsOf: Self.pbxprojURL, encoding: .utf8)
        let objectsRangeStart = try #require(content.range(of: "objects = {"))
        let objectsContent = String(content[objectsRangeStart.upperBound...])

        let pattern = #"^\t\t([0-9A-F]{24}) /\* .* \*/ = \{"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(objectsContent.startIndex..<objectsContent.endIndex, in: objectsContent)

        var seen = Set<String>()
        var duplicates: [String] = []
        for match in regex.matches(in: objectsContent, range: range) {
            guard let idRange = Range(match.range(at: 1), in: objectsContent) else { continue }
            let id = String(objectsContent[idRange])
            if !seen.insert(id).inserted {
                duplicates.append(id)
            }
        }

        #expect(!seen.isEmpty)
        #expect(duplicates.isEmpty, "Duplicate PBXObject IDs in project.pbxproj: \(duplicates)")
    }

    @Test
    func allSourceSwiftFilesHaveFileReferencesAndBuildPhaseEntries() throws {
        let content = try String(contentsOf: Self.pbxprojURL, encoding: .utf8)

        let fileRefPattern = #"^\t\t([0-9A-F]{24}) /\* ([^/]+\.swift) \*/ = \{isa = PBXFileReference; .*path = ([^;]+);"#
        let fileRefRegex = try NSRegularExpression(pattern: fileRefPattern, options: [.anchorsMatchLines])
        let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)

        var fileRefByName: [String: String] = [:]
        for match in fileRefRegex.matches(in: content, range: fullRange) {
            guard let idRange = Range(match.range(at: 1), in: content),
                  let pathRange = Range(match.range(at: 3), in: content) else {
                continue
            }
            let id = String(content[idRange])
            let path = String(content[pathRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            fileRefByName[path] = id
        }

        let buildFilePattern = #"^\t\t([0-9A-F]{24}) /\* ([^/]+\.swift) in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* [^*]+ \*/; \};"#
        let buildFileRegex = try NSRegularExpression(pattern: buildFilePattern, options: [.anchorsMatchLines])

        var buildFileIDsByFileRef: [String: String] = [:]
        for match in buildFileRegex.matches(in: content, range: fullRange) {
            guard let buildIDRange = Range(match.range(at: 1), in: content),
                  let fileRefRange = Range(match.range(at: 3), in: content) else {
                continue
            }
            let buildID = String(content[buildIDRange])
            let fileRefID = String(content[fileRefRange])
            buildFileIDsByFileRef[fileRefID] = buildID
        }

        let sourcesPhaseStart = try #require(content.range(of: "/* Begin PBXSourcesBuildPhase section */"))
        let sourcesPhaseEnd = try #require(content.range(of: "/* End PBXSourcesBuildPhase section */"))
        let sourcesPhaseContent = String(content[sourcesPhaseStart.upperBound..<sourcesPhaseEnd.lowerBound])

        let phaseEntryPattern = #"^\t\t\t\t([0-9A-F]{24}) /\* ([^/]+\.swift) in Sources \*/,"#
        let phaseEntryRegex = try NSRegularExpression(pattern: phaseEntryPattern, options: [.anchorsMatchLines])
        let phaseRange = NSRange(sourcesPhaseContent.startIndex..<sourcesPhaseContent.endIndex, in: sourcesPhaseContent)

        var sourcesPhaseBuildIDs = Set<String>()
        for match in phaseEntryRegex.matches(in: sourcesPhaseContent, range: phaseRange) {
            guard let buildIDRange = Range(match.range(at: 1), in: sourcesPhaseContent) else { continue }
            sourcesPhaseBuildIDs.insert(String(sourcesPhaseContent[buildIDRange]))
        }

        let sourcesRoot = Self.repositoryRoot.appendingPathComponent("Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        )

        var sourceFiles: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            sourceFiles.append(fileURL.lastPathComponent)
        }
        #expect(!sourceFiles.isEmpty)

        for fileName in sourceFiles.sorted() {
            let fileRefID = fileRefByName[fileName]
            #expect(fileRefID != nil, "Missing PBXFileReference for \(fileName)")
            if let fileRefID {
                let buildFileID = buildFileIDsByFileRef[fileRefID]
                #expect(buildFileID != nil, "Missing PBXBuildFile for \(fileName)")
                if let buildFileID {
                    #expect(sourcesPhaseBuildIDs.contains(buildFileID), "Missing PBXSourcesBuildPhase entry for \(fileName)")
                }
            }
        }
    }
}
