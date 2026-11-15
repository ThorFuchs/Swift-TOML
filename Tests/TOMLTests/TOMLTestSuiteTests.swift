// SPDX-License-Identifier: Apache-2.0
import Foundation
import JSON
import Testing
@testable import TOML

/// Runs the vendored toml-test cases for TOML 1.0 (toml-test v2.2.0, `files-toml-1.0.0`).
///
/// Outcomes per case:
/// - `pass`: an invalid case throws, or a valid case matches its expected JSON.
/// - `policy`: a valid case is rejected on purpose because JSON cannot represent it
///   (`inf` and `nan`). See README "Conformance".
/// - `fail`: anything else. These must be exactly `knownFailures`, which the README lists.
struct TOMLTestSuiteTests {
    enum Outcome: Equatable { case pass, policy(TOMLError.Code), fail(String) }

    static let policyCodes: Set<TOMLError.Code> = [.nonFiniteNumber]

    /// Valid cases that must be rejected with a policy code. Keep in sync with README.md.
    static let expectedPolicyRejections: Set<String> = [
        "valid/comment/after-literal-no-ws",
        "valid/float/inf-and-nan",
        "valid/spec-1.0.0/float-2",
    ]

    /// Cases the parser does not handle correctly yet. Keep in sync with README.md.
    static let knownFailures: Set<String> = []

    static func suiteDirectory() throws -> URL {
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return fixtures.appendingPathComponent("toml-test")
    }

    /// Case names (`valid/...` or `invalid/...`, without extension) from `files-toml-1.0.0`.
    static func caseNames() throws -> [String] {
        let list = try String(contentsOf: suiteDirectory().appendingPathComponent("files-toml-1.0.0"), encoding: .utf8)
        return list.split(whereSeparator: \.isNewline)
            .filter { $0.hasSuffix(".toml") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    static func run(_ name: String) throws -> Outcome {
        let dir = try suiteDirectory()
        let toml = try [UInt8](Data(contentsOf: dir.appendingPathComponent(name + ".toml")))
        let expectsError = name.hasPrefix("invalid/")
        let actual: JSON
        do {
            actual = try TOMLParser().parse(toml)
        } catch {
            if expectsError {
                if ProcessInfo.processInfo.environment["TOML_SUITE_VERBOSE"] != nil { print("rejected \(name) \(error.code) \(error)") }
                return .pass
            }
            if policyCodes.contains(error.code) { return .policy(error.code) }
            return .fail("unexpected error \(error.code) \(error)")
        }
        if expectsError { return .fail("expected an error, parsed \(actual)") }
        let tagged = try JSON.parse([UInt8](Data(contentsOf: dir.appendingPathComponent(name + ".json"))))
        if let mismatch = compare(actual, tagged, path: "") { return .fail(mismatch) }
        return .pass
    }

    /// Compares a parse result with toml-test's tagged JSON (`{"type": ..., "value": ...}` for scalars).
    static func compare(_ actual: JSON, _ expected: JSON, path: String) -> String? {
        switch expected {
        case .array(let items):
            guard case .array(let values) = actual, values.count == items.count else {
                return "\(path): expected an array of \(items.count), got \(actual)"
            }
            for (index, item) in items.enumerated() {
                if let mismatch = compare(values[index], item, path: "\(path)[\(index)]") { return mismatch }
            }
            return nil
        case .object(let object):
            if object.count == 2, case .string(let type)? = object["type"], case .string(let value)? = object["value"] {
                return compareScalar(actual, type: type, value: value, path: path)
            }
            guard case .object(let members) = actual, members.count == object.count else {
                return "\(path): expected a table with \(object.count) keys, got \(actual)"
            }
            for member in object {
                guard let value = members[member.key] else { return "\(path): missing key \(member.key.string)" }
                if let mismatch = compare(value, member.value, path: "\(path).\(member.key.string)") { return mismatch }
            }
            return nil
        default:
            return "\(path): unexpected expected value \(expected)"
        }
    }

    static func compareScalar(_ actual: JSON, type: String, value: String, path: String) -> String? {
        let ok: Bool
        switch type {
        case "string":
            ok = actual == .string(value)
        case "bool":
            ok = actual == .boolean(value == "true")
        case "integer":
            ok = (try? JSON.number(parsing: value)) == actual
        case "float":
            // toml-test spells floats as binary64 values; compare exactly first, then as binary64.
            if (try? JSON.number(parsing: value)) == actual {
                ok = true
            } else if case .number(let number) = actual, let lexeme = number.originalLexeme, let a = Double(lexeme), let e = Double(value) {
                ok = a == e
            } else {
                ok = false
            }
        case "datetime", "datetime-local", "date-local", "time-local":
            // Values are kept as source text; toml-test normalizes the separator, 'z' and
            // fractional seconds (".6" becomes ".600").
            guard case .string(let text) = actual else { ok = false; break }
            ok = normalizeDateTime(text) == normalizeDateTime(value)
        default:
            return "\(path): unknown type \(type)"
        }
        return ok ? nil : "\(path): expected \(type) \(value), got \(actual)"
    }

    static func normalizeDateTime(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        if scalars.count > 10 && (scalars[10] == " " || scalars[10] == "t") && scalars[4] == "-" { scalars[10] = "T" }
        if scalars.last == "z" { scalars[scalars.count - 1] = "Z" }
        // Drop trailing zeros of fractional seconds, and the dot if nothing remains.
        if let dot = scalars.firstIndex(of: ".") {
            var end = dot + 1
            while end < scalars.count && ("0"..."9").contains(scalars[end]) { end += 1 }
            var keep = end
            while keep > dot + 1 && scalars[keep - 1] == "0" { keep -= 1 }
            if keep == dot + 1 { keep = dot }
            scalars.removeSubrange(keep..<end)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    @Test("toml-test 1.0: every case passes, is a deliberate policy rejection, or is a listed known failure")
    func suite() throws {
        var failures: [String: String] = [:]
        var policies: Set<String> = []
        var validPasses = 0, invalidPasses = 0
        let names = try Self.caseNames()
        for name in names {
            switch try Self.run(name) {
            case .pass:
                if name.hasPrefix("valid/") { validPasses += 1 } else { invalidPasses += 1 }
            case .policy: policies.insert(name)
            case .fail(let reason): failures[name] = reason
            }
        }
        let unexpected = failures.filter { !Self.knownFailures.contains($0.key) }
        let fixed = Self.knownFailures.subtracting(failures.keys)
        print("toml-test 1.0: \(names.count) cases; valid \(validPasses) pass, \(policies.count) policy; invalid \(invalidPasses) rejected; \(failures.count) fail")
        for (name, reason) in unexpected.sorted(by: { $0.key < $1.key }) {
            Issue.record("\(name): \(reason)")
        }
        #expect(fixed.isEmpty, "now passing, remove from knownFailures: \(fixed.sorted())")
        #expect(policies == Self.expectedPolicyRejections)
        #expect(names.count == 679)
    }
}
