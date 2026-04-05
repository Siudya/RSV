= RSV Documentation

Detailed RSV documentation lives in this directory as Typst source files.

== Contents

- `guide.typ`: usage flow, elaboration model, and a worked module example.
- `reference.typ`: DSL entry points, naming notes, and semantic rules.
- `examples.typ`: examples directory feature coverage.

== Build

Compile the combined documentation with:

```bash
xmake doc
```

This generates `build/rsv_doc.pdf`.

#include "guide.typ"

#include "reference.typ"

#include "examples.typ"
