# Frontmatter

Split and parse Hugo-style TOML frontmatter at the start of a Markdown file.

## Overview

A file has TOML frontmatter only when its first line is `+++`. An optional UTF-8 byte
order mark before it is allowed. The frontmatter ends at the next line that is `+++`.
Fence lines may have trailing spaces or tabs, and line endings may be LF or CRLF.

```markdown
+++
title = "Hello"
tags = ["a", "b"]
+++
# Heading
```

``TOMLParser/parseFrontmatter(_:)`` splits and parses in one step:

```swift
let file = Array(markdown.utf8)
if let front = try TOMLParser().parseFrontmatter(file) {
    front.data           // {"title": "Hello", "tags": ["a", "b"]}
    front.body           // the bytes of "# Heading\n"
    front.bodyStartLine  // 5
} else {
    // No frontmatter; the whole file is body.
}
```

- A file without an opening fence returns `nil`.
- An empty frontmatter block parses to an empty object.
- An opening fence with no closing fence is
  ``TOMLError/Code-swift.enum/unterminatedFrontmatter``. The parser never guesses where
  the body starts.
- ``TOMLLimits/maxInputBytes`` applies to the whole file.
- Error positions from ``TOMLParser/parseFrontmatter(_:)`` refer to lines of the whole
  file.

To only split the file, without parsing the TOML, use ``TOMLFrontmatter/split(_:)``.
