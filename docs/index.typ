= RSV 文档总览

本目录保存 RSV 的 Typst 文档源文件。README 负责仓库首页级概览，这里的文档负责更细的 DSL 说明、示例说明与特性覆盖。

== 文档目录

- `guide.typ`：使用流程、`xmake` 示例入口、`BundleDef` 类型、命令行入口、导入与自动去重说明。
- `reference.typ`：DSL 入口、语义规则、命名约定与 API 细节。
- `examples.typ`：内置示例目录、别名、特性摘要与测试覆盖矩阵。

== 构建方式

使用下面的命令编译整本文档：

```bash
xmake doc
```

生成结果位于 `build/rsv_doc.pdf`。

#include "guide.typ"

#include "reference.typ"

#include "examples.typ"
