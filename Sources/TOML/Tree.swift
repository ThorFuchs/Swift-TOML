// SPDX-License-Identifier: Apache-2.0
// The mutable document tree built while parsing, and its conversion to exact JSON.
import JSON

/// How a table came into existence; TOML's redefinition rules depend on it.
enum TableOrigin {
    /// Created as an intermediate of a `[header]` or `[[header]]` path; a later header may define it.
    case implicit
    /// Defined by a `[header]` or as an element of a `[[header]]` array.
    case header
    /// Created by a dotted key; only dotted keys of the same section may extend it.
    case dotted
    /// An inline table `{ ... }`.
    case inline
}

struct Node {
    enum Kind {
        case table
        /// An array of tables created by `[[header]]`; later headers may append to it.
        case tableArray
        /// An inline array `[ ... ]`; it is a value and cannot be extended.
        case array
        case scalar
    }

    var kind: Kind
    var origin: TableOrigin = .implicit
    /// The header section (or inline table) whose dotted keys may extend this table.
    var section = 0
    /// True for tables inside an inline table; nothing may be added after it closes.
    var frozen = false
    /// Members in source order (tables).
    var keys: [JSONKey] = []
    var lookup: [JSONKey: Int] = [:]
    /// Elements in source order (arrays).
    var items: [Int] = []
    var scalar: JSON = .null
    /// Nesting depth; the root table is 1.
    var depth: Int
}

struct Tree {
    private(set) var nodes: [Node]
    let limits: TOMLLimits

    init(limits: TOMLLimits) {
        self.limits = limits
        nodes = [Node(kind: .table, origin: .header, depth: 1)]
    }

    static let root = 0

    subscript(index: Int) -> Node {
        get { nodes[index] }
        _modify { yield &nodes[index] }
    }

    /// Appends a node, enforcing the depth and node limits at the node's source offset.
    mutating func add(_ node: Node, at offset: Int, in bytes: [UInt8]) throws(TOMLError) -> Int {
        guard node.kind == .scalar || node.depth <= limits.maxDepth else {
            throw TOMLError(.depthLimitExceeded, "nesting is deeper than \(limits.maxDepth)", offset: offset, in: bytes)
        }
        guard nodes.count <= limits.maxNodes else {
            throw TOMLError(.nodeLimitExceeded, "document has more than \(limits.maxNodes) values", offset: offset, in: bytes)
        }
        nodes.append(node)
        return nodes.count - 1
    }

    mutating func attach(_ child: Int, as key: JSONKey, to table: Int) {
        nodes[table].keys.append(key)
        nodes[table].lookup[key] = child
    }

    /// Converts the tree to JSON without recursion. Every child has a larger index than
    /// its parent (nodes are only ever attached to existing parents), so a single pass
    /// from the last node to the first sees all children before their parent.
    func json() throws(TOMLError) -> JSON {
        var jsonLimits = JSONLimits(profile: .offline)
        jsonLimits[.maxDepth] = max(jsonLimits[.maxDepth], UInt64(max(0, limits.maxDepth)) + 2)
        jsonLimits[.nodes] = max(jsonLimits[.nodes], UInt64(max(0, limits.maxNodes)) + 2)
        jsonLimits[.objectMembers] = max(jsonLimits[.objectMembers], UInt64(max(0, limits.maxNodes)) + 1)
        jsonLimits[.arrayItems] = max(jsonLimits[.arrayItems], UInt64(max(0, limits.maxNodes)) + 1)

        var built = [JSON?](repeating: nil, count: nodes.count)
        var index = nodes.count - 1
        while index >= 0 {
            let node = nodes[index]
            switch node.kind {
            case .scalar:
                built[index] = node.scalar
            case .array, .tableArray:
                var values: [JSON] = []
                values.reserveCapacity(node.items.count)
                for item in node.items {
                    values.append(built[item] ?? .null)
                    built[item] = nil
                }
                built[index] = .array(values)
            case .table:
                var members: [JSONMember] = []
                members.reserveCapacity(node.keys.count)
                for key in node.keys {
                    guard let child = node.lookup[key] else { continue }
                    members.append(JSONMember(key, value: built[child] ?? .null))
                    built[child] = nil
                }
                do {
                    built[index] = .object(try JSONObject(members: members, limits: jsonLimits))
                } catch {
                    throw TOMLError(.nodeLimitExceeded, "table exceeds Swift-JSON construction limits", line: 1, column: 1)
                }
            }
            index -= 1
        }
        guard let root = built[0] else {
            throw TOMLError(.syntax, "internal tree state error", line: 1, column: 1)
        }
        return root
    }
}
