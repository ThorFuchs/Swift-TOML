// SPDX-License-Identifier: Apache-2.0
import JSON
import Testing
import TOML

struct FrontmatterTests {
    func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    @Test("splits +++ frontmatter from the body and reports the body's first line")
    func split() throws {
        let split = try #require(try TOMLFrontmatter.split(bytes("+++\ntitle = \"Hi\"\n+++\n# Body\n")))
        #expect(split.toml == bytes("title = \"Hi\"\n"))
        #expect(split.tomlStartLine == 2)
        #expect(split.body == bytes("# Body\n"))
        #expect(split.bodyStartLine == 4)
    }

    @Test("a file that does not start with +++ has no frontmatter")
    func absent() throws {
        #expect(try TOMLFrontmatter.split(bytes("# Title\n+++\n")) == nil)
        #expect(try TOMLFrontmatter.split(bytes("---\na: 1\n---\n")) == nil)
        #expect(try TOMLFrontmatter.split(bytes("++++\n")) == nil)
        #expect(try TOMLParser().parseFrontmatter(bytes("plain text")) == nil)
    }

    @Test("CRLF line endings, a BOM and trailing blanks on fences are accepted")
    func crlfBOMAndBlanks() throws {
        let text = [0xEF, 0xBB, 0xBF] + bytes("+++ \r\na = 1\r\n+++\t\r\nbody")
        let parsed = try #require(try TOMLParser().parseFrontmatter(text))
        #expect(parsed.data == (try JSON.parse(#"{"a":1}"#)))
        #expect(parsed.body == bytes("body"))
        #expect(parsed.bodyStartLine == 4)
    }

    @Test("an empty block parses to an empty object and a closing fence at the end of input is allowed")
    func emptyBlock() throws {
        let parsed = try #require(try TOMLParser().parseFrontmatter(bytes("+++\n+++")))
        #expect(parsed.data == (try JSON.parse("{}")))
        #expect(parsed.body.isEmpty)
        #expect(parsed.bodyStartLine == 3)
    }

    @Test("an unclosed block fails with unterminatedFrontmatter")
    func unterminated() {
        #expect(throws: TOMLError.self) { try TOMLParser().parseFrontmatter(self.bytes("+++\na = 1\n")) }
        do {
            _ = try TOMLParser().parseFrontmatter(bytes("+++\na = 1\n"))
        } catch {
            #expect(error.code == .unterminatedFrontmatter)
        }
    }

    @Test("errors inside frontmatter report lines of the whole file")
    func fileRelativeLines() {
        do {
            _ = try TOMLParser().parseFrontmatter(bytes("+++\na = 1\na = 2\n+++\n"))
            Issue.record("expected an error")
        } catch {
            #expect(error.code == .duplicateKey)
            #expect(error.line == 3)
            #expect(error.column == 1)
        }
    }

    @Test("maxInputBytes applies to the whole file")
    func inputLimit() {
        do {
            _ = try TOMLParser(limits: TOMLLimits(maxInputBytes: 8)).parseFrontmatter(bytes("+++\n+++\nlong body text"))
            Issue.record("expected an error")
        } catch {
            #expect(error.code == .inputTooLarge)
        }
    }
}
