= RSV Documentation

Detailed RSV documentation lives in this directory as Typst source files.

== Contents

- `guide.typ`: usage flow, xmake-based example runner, editor setup, and worked modules.
- `reference.typ`: DSL entry points, naming notes, and semantic rules.
- `examples.typ`: built-in example aliases, xmake usage, and feature coverage.

== Build

Compile the combined documentation with:

```bash
xmake doc
```

This generates `build/rsv_doc.pdf`.

#include "guide.typ"

#include "reference.typ"

#include "examples.typ"
