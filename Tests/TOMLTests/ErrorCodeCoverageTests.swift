// SPDX-License-Identifier: Apache-2.0
import Testing
import TOML

/// One minimal reproducer per error code. Adding a `TOMLError.Code` case without a
/// reproducer here fails the test plan, not just a review checklist.
struct ErrorCodeCoverageTests {
    static func reproduce(_ code: TOMLError.Code) async -> TOMLError? {
        func parse(_ text: String, _ limits: TOMLLimits = .default) -> TOMLError? {
            do { _ = try TOMLParser(limits: limits).parse(text); return nil } catch { return error }
        }
        switch code {
        case .invalidEncoding:
            do { _ = try TOMLParser().parse([0x61, 0x3D, 0x22, 0xC3, 0x28, 0x22]); return nil } catch { return error }
        case .controlCharacter: return parse("a = \"\u{0}\"")
        case .syntax: return parse("a = [1, 2")
        case .invalidEscape: return parse(#"a = "\x41""#)
        case .invalidNumber: return parse("a = 007")
        case .invalidDateTime: return parse("a = 2021-02-29")
        case .nonFiniteNumber: return parse("a = inf")
        case .numberOutOfRange: return parse("a = 1e9999999999")
        case .duplicateKey: return parse("a = 1\na = 2")
        case .tableRedefinition: return parse("[a]\n[a]")
        case .unterminatedFrontmatter:
            do { _ = try TOMLFrontmatter.split(Array("+++\na = 1\n".utf8)); return nil } catch { return error }
        case .inputTooLarge: return parse("a = 1", TOMLLimits(maxInputBytes: 1))
        case .depthLimitExceeded: return parse("a = [[1]]", TOMLLimits(maxDepth: 2))
        case .nodeLimitExceeded: return parse("a = [1, 2]", TOMLLimits(maxNodes: 2))
        case .cancelled:
            return await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return parse("a = 1")
            }.value
        }
    }

    @Test("every error code has a minimal input that produces exactly that code", arguments: TOMLError.Code.allCases)
    func everyCodeIsReproducible(_ code: TOMLError.Code) async throws {
        let error = try #require(await Self.reproduce(code), "no error for \(code)")
        #expect(error.code == code)
        #expect(error.line >= 1 && error.column >= 1)
        #expect(!error.message.isEmpty)
        #expect(!error.message.contains("/Users/") && !error.message.contains("/home/"))
    }
}
