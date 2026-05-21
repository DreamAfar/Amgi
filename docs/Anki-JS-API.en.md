# Anki JS API

Amgi exposes a set of capabilities on the review card screen that are compatible with the **AnkiDroid JavaScript API**, unified under the name **Anki JS API**.

It allows card templates to use JavaScript to:

- Read the current reviewer state
- Control answer reveal and grading
- Read or modify selected parts of the current card / note state
- Invoke TTS
- Open search or receive search callback results

## Availability

- Available only on the **review card screen**
- Available only inside card-template JavaScript
- Compatible entry points:
  - `window.AnkiDroidJS`
  - `window.AnkiJS`

## Initialization

Recommended:

```html
<script>
  const api = new AnkiDroidJS({
    version: "0.0.3",
    developer: "your-email-or-id"
  });
</script>
```

You can also use:

```html
<script>
  const api = new AnkiJS({
    version: "0.0.3",
    developer: "your-email-or-id"
  });
</script>
```

Notes:

- `version` and `developer` must currently be non-empty
- The current internal Amgi API version is `0.0.3`

## Return Value Convention

Most APIs return:

```json
{
  "success": true,
  "value": ...
}
```

Some APIs return raw strings directly:

- `ankiGetDeckName()`
- `ankiGetNextTime1()`
- `ankiGetNextTime2()`
- `ankiGetNextTime3()`
- `ankiGetNextTime4()`

## Supported APIs

### 1. Reviewer State

- `ankiGetNewCardCount()`
- `ankiGetLrnCardCount()`
- `ankiGetRevCardCount()`
- `ankiGetETA()`
- `ankiIsInNightMode()`
- `ankiIsDisplayingAnswer()`
- `ankiGetDeckName()`

Example:

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

Notes:

- `ankiGetETA()` is currently an **estimate**
- It is not guaranteed to be sourced identically to AnkiDroid

### 2. Current Card Information

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

Example:

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

### 3. Reviewer Controls

- `ankiShowAnswer()`
- `ankiAnswerEase1()`
- `ankiAnswerEase2()`
- `ankiAnswerEase3()`
- `ankiAnswerEase4()`

Example:

```html
<button onclick="api.ankiShowAnswer()">Show Answer</button>
<button onclick="api.ankiAnswerEase1()">Again</button>
<button onclick="api.ankiAnswerEase2()">Hard</button>
<button onclick="api.ankiAnswerEase3()">Good</button>
<button onclick="api.ankiAnswerEase4()">Easy</button>
```

Notes:

- If the front side is still showing, `ankiAnswerEase1~4()` first performs the reveal-answer step
- Typed-answer cards automatically pass through the current input

### 4. Card / Note Actions

- `ankiMarkCard(1)`
- `ankiToggleFlag("red")`
- `ankiBuryCard(1)`
- `ankiBuryNote(1)`
- `ankiSuspendCard(1)`
- `ankiSuspendNote(1)`
- `ankiResetProgress(1)`
- `ankiSetCardDue("3")`

Example:

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

Supported flag values:

- `"none"`
- `"red"`
- `"orange"`
- `"green"`
- `"blue"`
- `"pink"`
- `"turquoise"` / `"cyan"`
- `"purple"`

Notes:

- The parameter to `ankiMarkCard(1)` is currently kept only for compatibility
- `ankiBury* / ankiSuspend* / ankiResetProgress / ankiSetCardDue` may cause the reviewer to jump to the next card immediately

### 5. Tags

- `ankiGetNoteTags()`
- `ankiSetNoteTags([...])`
- `ankiAddTagToNote(noteId, tag)`
- `ankiAddTagToCard()`

Example:

```html
<script>
  async function testTags() {
    await api.ankiSetNoteTags(["amgi_test", "js_api"]);
    const tags = await api.ankiGetNoteTags();
    console.log(tags);
  }
</script>
```

Notes:

- `ankiSetNoteTags([...])` **replaces the full current note tag set**
- Spaces are automatically converted to underscores
- `ankiAddTagToNote()` still works, but `ankiSetNoteTags()` is recommended
- In Amgi, `ankiAddTagToCard()` currently:
  - opens the current note editor
  - lets the user edit tags manually
  - does not behave like AnkiDroid's native tag dialog

### 6. TTS

- `ankiTtsFieldModifierIsAvailable()`
- `ankiTtsIsSpeaking()`
- `ankiTtsStop()`
- `ankiTtsSetLanguage(lang)`
- `ankiTtsSetPitch(pitch)`
- `ankiTtsSetSpeechRate(rate)`
- `ankiTtsSpeak(text, queueMode)`

Example:

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

Notes:

- `ankiTtsFieldModifierIsAvailable()` currently always returns `false`
- `queueMode` is currently retained as a compatibility parameter and does not represent full AnkiDroid queue semantics

### 7. Search

- `ankiSearchCard(query)`
- `ankiSearchCardWithCallback(query)`

#### `ankiSearchCard(query)`

In Amgi, the current behavior is:

- keep the reviewer open
- present a Browse sheet
- prefill the query
- run the search automatically

Example:

```html
<button onclick='api.ankiSearchCard("anki")'>Search</button>
```

#### `ankiSearchCardWithCallback(query)`

This API does not leave the current card screen. Instead, it sends search results back to the template JavaScript.

Recommended usage:

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

Each callback result item typically includes:

- `cardId`
- `noteId`
- `fieldsData`

### 8. UI Helpers

- `ankiShowToast(text, shortLength)`
- `ankiEnableHorizontalScrollbar(enabled)`
- `ankiEnableVerticalScrollbar(enabled)`

Example:

```html
<script>
  async function toastDemo() {
    await api.ankiShowToast("Hello from Amgi JS API", true);
  }
</script>
```

## Compatibility Helper Functions

Amgi also provides a minimal hook compatibility layer:

- `addHook(name, callback)`
- `runHook(name, arg)`

Mainly used for:

- dispatching `ankiSearchCardWithCallback()` results

Recommended usage:

```html
<script>
  addHook("ankiSearchCard", function(result) {
    console.log(result);
  });
</script>
```

## Currently Unsupported APIs

The following AnkiDroid JavaScript API capabilities are **not currently implemented**:

- `ankiIsInFullscreen`
- `ankiIsTopbarShown`
- `ankiIsActiveNetworkMetered`
- `ankiShowNavigationDrawer`
- `ankiShowOptionsMenu`
- `ankiSttSetLanguage`
- `ankiSttStart`
- `ankiSttStop`

## Compatibility Notes

The goal of Amgi's Anki JS API is to:

- prioritize compatibility with common interactive card templates
- reuse existing reviewer / Browse / TTS / card-action capabilities as much as possible

However, it is not a line-by-line 1:1 platform reimplementation of the AnkiDroid JavaScript API. In particular:

- some APIs provide approximate semantics rather than Android-native behavior
- `ankiGetETA()` is an estimate
- `ankiAddTagToCard()` is an approximate implementation
- search-related behavior is adapted to Amgi's current iOS UI structure

## Minimal Example

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

## Debugging Tips

- test in the reviewer's front template first
- first confirm that `AnkiDroidJS` exists
- start with `console.log()` or `<pre>` output
- for APIs that change scheduling state, it is safer to trigger them near the end of testing:
  - `ankiBury*`
  - `ankiSuspend*`
  - `ankiResetProgress`
  - `ankiSetCardDue`
  - `ankiAnswerEase1~4`
