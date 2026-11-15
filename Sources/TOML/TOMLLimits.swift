// SPDX-License-Identifier: Apache-2.0

/// Explicit resource ceilings. Exceeding any of them fails the parse; nothing is truncated.
public struct TOMLLimits: Sendable, Equatable {
    /// Maximum input size in bytes.
    public var maxInputBytes: Int
    /// Maximum nesting of tables and arrays. The root table counts as depth 1, so
    /// `a = [1]` has depth 2 and `[a.b]` has depth 3.
    public var maxDepth: Int
    /// Maximum number of values in the result: tables, arrays and scalars, not counting
    /// the root table.
    public var maxNodes: Int

    /// Creates limits; every value must be positive.
    public init(
        maxInputBytes: Int = 8 * 1024 * 1024,
        maxDepth: Int = 128,
        maxNodes: Int = 1_000_000
    ) {
        self.maxInputBytes = maxInputBytes
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }

    /// 8 MiB input, depth 128, 1,000,000 values.
    public static let `default` = TOMLLimits()
}
