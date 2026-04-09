# Pull Request Template & Commit Convention

## PR 模板

在 `.github/pull_request_template.md` 中创建（如果不存在）：

```markdown
## 📝 PR 描述

**目的**: 
[简要说明此 PR 的目的]

**类型**: 
- [ ] 新功能
- [ ] Bug 修复
- [ ] 性能优化
- [ ] 代码重构
- [ ] 文档更新

## 🎯 关联的 Issue

Closes #[issue number]

## ✅ 变更清单

- [ ] 遵循代码风格规范
- [ ] 添加或更新了测试
- [ ] 更新了相关文档
- [ ] 没有引入新的警告
- [ ] 本地测试通过

## 🔍 代码审查检查清单

### 依赖注入
- [ ] 所有 @DependencyClient 正确标注
- [ ] 导入了 Dependencies 框架
- [ ] 没有循环导入

### 异步操作
- [ ] 使用 async/await 而非回调
- [ ] @MainActor 标注正确
- [ ] 没有内存泄漏

### 错误处理
- [ ] 所有网络调用都有错误处理
- [ ] 使用 throws 而不是 try?
- [ ] 错误消息对用户友好

### UI 更新
- [ ] @State 更新正确
- [ ] 只在 @MainActor 上更新 UI
- [ ] 性能良好（< 60fps）

## 📸 截图 (如适用)

[添加截图或 GIF]

## 🧪 测试说明

如何测试此更改：

1. [步骤1]
2. [步骤2]
3. [步骤3]

预期结果：
[描述预期的行为]

## 其他注意事项

[任何需要特别关注的地方]
```

---

## 📋 Commit 规范

### 格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type（必需）

| Type | 说明 | 例子 |
|------|------|------|
| `feat` | 新功能 | `feat(review): add card suspend button` |
| `fix` | Bug 修复 | `fix(sync): handle network timeout` |
| `docs` | 文档更新 | `docs: update developer guide` |
| `style` | 代码格式（未改逻辑） | `style: format imports` |
| `refactor` | 重构代码 | `refactor(deck): simplify tree logic` |
| `perf` | 性能优化 | `perf(review): cache card HTML` |
| `test` | 测试相关 | `test(card-client): add unit tests` |
| `chore` | 构建、依赖等 | `chore: update dependencies` |

### Scope（推荐）

指定改动的范围：

```
feat(review): ...      // ReviewView
fix(sync): ...         // Sync 功能
docs(client): ...      // 文档关于 Client
refactor(deck): ...    // Deck 相关
```

### Subject（提交标题）

- ✅ 使用祈使句（"add" 而不是 "added" 或 "adds"）
- ✅ 不要大写首字母
- ✅ 结尾不加句号
- ✅ 限制在 50 个字符以内

**好的例子**:
```
feat(review): add card suspend functionality
fix(browse): resolve note deletion crash
docs: update API documentation
```

**不好的例子**:
```
updated the review view
Fixed a bug.
REFACTOR EVERYTHING
```

### Body（提交主体）

- 说明**是什么**和**为什么**，而不是**如何**
- 每行 72 个字符左右换行
- 使用过去式

**例子**:
```
Add suspend functionality to card review workflow.

Users can now long-press on cards during review to
access a context menu with options including suspend,
bury, and undo. This improves the learning experience
by allowing quick card management without leaving
the review session.

Implements CardClient suspend/bury/undo APIs.
```

### Footer（提交页脚）

用于关联 Issue 和破坏性变更：

```
Closes #123
Refs #456
Breaking-Change: CardClient API now requires songRequestId
```

---

## 🔄 完整的 Commit 例子

### 例子 1: 新功能

```
feat(review): add card context menu with suspend/bury

Implement long-press gesture on cards to show context menu
with the following options:
- Suspend: Hide card until tomorrow
- Bury: Hide card until next interval  
- Flag: Mark card for review
- Edit: Quick edit of note
- Undo: Revert last action
- Card Info: View card statistics

Adds cardClient.suspend(), .bury(), and .flag() methods
that map to Rust backend scheduler APIs.

Closes #42
```

### 例子 2: Bug 修复

```
fix(sync): prevent data loss on incomplete sync

Ensure sync state is persisted before notifying UI
of completion. Previously, rapid back-to-back sync
attempts could cause data loss.

Add mutex lock to SyncSheet state management.
Verify sync completion with retry logic.

Fixes #38
```

### 例子 3: 文档更新

```
docs: add CardClient implementation guide

Provide clear examples of how to:
- Define new Client methods
- Implement with backend.invoke()  
- Wire dependencies in View
- Handle async/await correctly

Refs documentation task
```

---

## 🚀 Commit 技巧

### 使用交互式 Staging

```bash
git add -p
# 选择要提交的部分更改
```

### 修改最后一个 Commit

```bash
git commit --amend
# 修改提交信息
git commit --amend --no-edit
# 添加遗漏的文件而不改提交信息
```

### 查看提交历史

```bash
git log --oneline --graph --all
# 可视化提交历史
```

---

## 📊 PR 审查检查清单示例

**Reviewer 应该检查**:

- [ ] Commits 消息清晰且遵循规范
- [ ] 代码改动符合项目风格
- [ ] 测试覆盖率充分
- [ ] 没有性能回退
- [ ] 文档已更新
- [ ] 没有 secrets 在代码中泄露

---

## 🎓 最佳实践

### ✅ DO

- 使用小的、focused commits
- 每个 commit 是可编译的
- Commit message 详描变更原因
- 规律地 push 避免丢失工作

### ❌ DON'T

- 混合多个无关的更改
- Commit "WIP" 或 "test" 消息
- Squash 有用的中间 commits
- 强 push 到公共分支

---

## 示例工作流

```bash
# 1. 创建功能分支
git checkout -b feat/card-suspend

# 2. 分阶段提交
git add src/CardClient.swift
git commit -m "feat(client): add suspend method to CardClient API"

git add AnkiApp/Sources/Review/ReviewView.swift
git commit -m "feat(review): implement card context menu UI"

git add Tests/CardClientTests.swift
git commit -m "test(card-client): add suspend functionality tests"

# 3. 推送到远程
git push origin feat/card-suspend

# 4. 创建 Pull Request
# 在 GitHub 上提交 PR，填写模板

# 5. 根据 Review 意见调整
git add .
git commit -m "fix: address review comments"
git push origin feat/card-suspend

# 6. 合并
# 一旦获批，可以 Squash 和 Merge
```

---

## 参考资源

- [Angular 提交规范](https://github.com/angular/angular/blob/master/CONTRIBUTING.md#commit)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Git 最佳实践](https://git-scm.com/book/en/v2)

