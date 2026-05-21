# Anki JS API

Amgi 在复习卡片页内提供一组兼容 **AnkiDroid JavaScript API** 的能力，统一对外命名为 **Anki JS API**。

它允许卡片模板通过 JavaScript：

- 读取当前 reviewer 状态
- 控制显示答案与评分
- 读取或修改当前卡片 / 笔记的部分状态
- 调用 TTS
- 打开搜索或获取搜索回调结果

## 适用范围

- 仅在 **复习卡片页** 可用
- 仅在卡片模板的 JavaScript 中可用
- 兼容入口：
  - `window.AnkiDroidJS`
  - `window.AnkiJS`

## 初始化

推荐写法：

```html
<script>
  const api = new AnkiDroidJS({
    version: "0.0.3",
    developer: "your-email-or-id"
  });
</script>
```

也可以使用：

```html
<script>
  const api = new AnkiJS({
    version: "0.0.3",
    developer: "your-email-or-id"
  });
</script>
```

说明：

- `version` 与 `developer` 目前必须传非空值
- 当前 Amgi 内部 API 版本为 `0.0.3`

## 返回值约定

大多数接口会返回：

```json
{
  "success": true,
  "value": ...
}
```

少数接口直接返回原始字符串：

- `ankiGetDeckName()`
- `ankiGetNextTime1()`
- `ankiGetNextTime2()`
- `ankiGetNextTime3()`
- `ankiGetNextTime4()`

## 支持的接口

### 1. Reviewer 状态读取

- `ankiGetNewCardCount()`
- `ankiGetLrnCardCount()`
- `ankiGetRevCardCount()`
- `ankiGetETA()`
- `ankiIsInNightMode()`
- `ankiIsDisplayingAnswer()`
- `ankiGetDeckName()`

示例：

```html
<script>
  async function loadCounts() {
    const newCount = await api.ankiGetNewCardCount();
    const lrnCount = await api.ankiGetLrnCardCount();
    const revCount = await api.ankiGetRevCardCount();
    const eta = await api.ankiGetETA();
    console.log(newCount, lrnCount, revCount, eta);
  }
</script>
```

说明：

- `ankiGetETA()` 当前为 **估算值**
- 不保证与 AnkiDroid 完全同源

### 2. 当前卡片信息读取

- `ankiGetCardMark()`
- `ankiGetCardFlag()`
- `ankiGetCardReps()`
- `ankiGetCardInterval()`
- `ankiGetCardFactor()`
- `ankiGetCardMod()`
- `ankiGetCardId()`
- `ankiGetCardNid()`
- `ankiGetCardType()`
- `ankiGetCardDid()`
- `ankiGetCardLeft()`
- `ankiGetCardODid()`
- `ankiGetCardODue()`
- `ankiGetCardQueue()`
- `ankiGetCardLapses()`
- `ankiGetCardDue()`
- `ankiGetNextTime1()`
- `ankiGetNextTime2()`
- `ankiGetNextTime3()`
- `ankiGetNextTime4()`

示例：

```html
<script>
  async function loadCardInfo() {
    const cardId = await api.ankiGetCardId();
    const noteId = await api.ankiGetCardNid();
    const due = await api.ankiGetCardDue();
    const nextGood = await api.ankiGetNextTime3();
    console.log({ cardId, noteId, due, nextGood });
  }
</script>
```

### 3. Reviewer 控制

- `ankiShowAnswer()`
- `ankiAnswerEase1()`
- `ankiAnswerEase2()`
- `ankiAnswerEase3()`
- `ankiAnswerEase4()`

示例：

```html
<button onclick="api.ankiShowAnswer()">Show Answer</button>
<button onclick="api.ankiAnswerEase1()">Again</button>
<button onclick="api.ankiAnswerEase2()">Hard</button>
<button onclick="api.ankiAnswerEase3()">Good</button>
<button onclick="api.ankiAnswerEase4()">Easy</button>
```

说明：

- 如果当前仍在正面，`ankiAnswerEase1~4()` 会先执行翻面语义
- typed answer 卡片会自动透传当前输入内容

### 4. 卡片 / 笔记操作

- `ankiMarkCard(1)`
- `ankiToggleFlag("red")`
- `ankiBuryCard(1)`
- `ankiBuryNote(1)`
- `ankiSuspendCard(1)`
- `ankiSuspendNote(1)`
- `ankiResetProgress(1)`
- `ankiSetCardDue("3")`

示例：

```html
<script>
  async function markAndFlag() {
    await api.ankiMarkCard(1);
    await api.ankiToggleFlag("red");
  }

  async function deferThreeDays() {
    await api.ankiSetCardDue("3");
  }
</script>
```

旗标支持值：

- `"none"`
- `"red"`
- `"orange"`
- `"green"`
- `"blue"`
- `"pink"`
- `"turquoise"` / `"cyan"`
- `"purple"`

说明：

- `ankiMarkCard(1)` 的参数当前仅作兼容占位
- `ankiBury* / ankiSuspend* / ankiResetProgress / ankiSetCardDue` 可能导致 reviewer 立刻跳到下一张卡

### 5. 标签相关

- `ankiGetNoteTags()`
- `ankiSetNoteTags([...])`
- `ankiAddTagToNote(noteId, tag)`
- `ankiAddTagToCard()`

示例：

```html
<script>
  async function testTags() {
    await api.ankiSetNoteTags(["amgi_test", "js_api"]);
    const tags = await api.ankiGetNoteTags();
    console.log(tags);
  }
</script>
```

说明：

- `ankiSetNoteTags([...])` 会 **覆盖当前 note 的整组标签**
- 空格会自动转换为下划线
- `ankiAddTagToNote()` 仍可用，但更推荐 `ankiSetNoteTags()`
- `ankiAddTagToCard()` 在 Amgi 中当前表现为：
  - 打开当前笔记编辑页
  - 由用户手动编辑标签
  - 不是 AnkiDroid 的原生 tag dialog

### 6. TTS

- `ankiTtsFieldModifierIsAvailable()`
- `ankiTtsIsSpeaking()`
- `ankiTtsStop()`
- `ankiTtsSetLanguage(lang)`
- `ankiTtsSetPitch(pitch)`
- `ankiTtsSetSpeechRate(rate)`
- `ankiTtsSpeak(text, queueMode)`

示例：

```html
<script>
  async function speakDemo() {
    await api.ankiTtsSetLanguage("en-US");
    await api.ankiTtsSetPitch("1.0");
    await api.ankiTtsSetSpeechRate("1.0");
    await api.ankiTtsSpeak("Hello from Amgi", 0);
  }
</script>
```

说明：

- `ankiTtsFieldModifierIsAvailable()` 当前固定返回 `false`
- `queueMode` 当前保留兼容参数，不代表完整复刻 AnkiDroid 队列语义

### 7. 搜索

- `ankiSearchCard(query)`
- `ankiSearchCardWithCallback(query)`

#### `ankiSearchCard(query)`

在 Amgi 中当前行为为：

- 保持 reviewer 不关闭
- 弹出一个 Browse sheet
- 自动带入关键词
- 自动执行搜索

示例：

```html
<button onclick='api.ankiSearchCard("anki")'>Search</button>
```

#### `ankiSearchCardWithCallback(query)`

该接口不会离开当前卡片页，而是将搜索结果回调给模板 JS。

推荐写法：

```html
<div id="searchResult"></div>

<script>
  function parseResult(result) {
    const container = document.getElementById("searchResult");
    container.innerHTML = "<pre>" + JSON.stringify(result, null, 2) + "</pre>";
  }

  if (typeof addHook === "function") {
    addHook("ankiSearchCard", parseResult);
  }

  async function runSearch() {
    await api.ankiSearchCardWithCallback("anki");
  }
</script>
```

回调结果中每项通常包含：

- `cardId`
- `noteId`
- `fieldsData`

### 8. UI 辅助

- `ankiShowToast(text, shortLength)`
- `ankiEnableHorizontalScrollbar(enabled)`
- `ankiEnableVerticalScrollbar(enabled)`

示例：

```html
<script>
  async function toastDemo() {
    await api.ankiShowToast("Hello from Amgi JS API", true);
  }
</script>
```

## 兼容辅助函数

Amgi 当前还提供最小 hook 兼容层：

- `addHook(name, callback)`
- `runHook(name, arg)`

主要用于：

- `ankiSearchCardWithCallback()` 的结果分发

推荐使用：

```html
<script>
  addHook("ankiSearchCard", function(result) {
    console.log(result);
  });
</script>
```

## 当前未支持的接口

以下 AnkiDroid JavaScript API 能力目前 **未接入**：

- `ankiIsInFullscreen`
- `ankiIsTopbarShown`
- `ankiIsActiveNetworkMetered`
- `ankiShowNavigationDrawer`
- `ankiShowOptionsMenu`
- `ankiSttSetLanguage`
- `ankiSttStart`
- `ankiSttStop`

## 兼容性说明

Amgi 的 Anki JS API 目标是：

- 优先兼容常见交互式卡片模板
- 尽量复用现有 reviewer / Browse / TTS / 卡片操作能力

但它并不是对 AnkiDroid JavaScript API 的逐行 1:1 平台复刻，因此请特别注意：

- 部分接口为近似语义，而非 Android 原生行为
- `ankiGetETA()` 是估算值
- `ankiAddTagToCard()` 是近似实现
- 搜索相关行为适配了 Amgi 当前的 iOS UI 结构

## 最小示例

```html
{{Front}}

<script>
  const api = new AnkiDroidJS({
    version: "0.0.3",
    developer: "demo@example.com"
  });

  async function demo() {
    const deckName = await api.ankiGetDeckName();
    const counts = await api.ankiGetRevCardCount();
    console.log(deckName, counts);
  }
</script>

<button onclick="api.ankiShowAnswer()">Show Answer</button>
<button onclick="api.ankiAnswerEase3()">Good</button>
<button onclick="api.ankiShowToast('Hello', true)">Toast</button>
<button onclick="api.ankiSearchCard('anki')">Search</button>
```

## 调试建议

- 优先在 reviewer 正面模板中测试
- 先确认 `AnkiDroidJS` 是否存在
- 先使用 `console.log()` 或 `<pre>` 输出结果
- 对会改变调度状态的接口，建议放到测试卡片的最后再点：
  - `ankiBury*`
  - `ankiSuspend*`
  - `ankiResetProgress`
  - `ankiSetCardDue`
  - `ankiAnswerEase1~4`
