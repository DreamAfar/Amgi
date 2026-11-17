//
//  GlossaryHTMLTests.swift
//  ReaderTests
//

import Foundation
import Reader
import Testing

struct GlossaryHTMLTests {
    private func styled(_ content: String, style: String = "") -> String {
        GlossaryHTML.styled(
            dictionary: "明鏡",
            glossaries: [DictionaryLookupGlossary(dictionary: "明鏡", content: content)],
            style: style
        )
    }

    @Test func plainTextKeepsItsLineBreaksAndIsEscaped() {
        let html = styled("a < b\nsecond line")
        #expect(html.contains("a &lt; b<br>second line"))
        #expect(html.hasPrefix(#"<div style="text-align: left;" class="yomitan-glossary"><div data-dictionary="明鏡"><i>(明鏡)</i> "#))
    }

    @Test func structuredContentCarriesTheClassesAndDataTheStylesheetSelects() {
        let content = #"""
        {"type":"structured-content","content":[
          {"tag":"div","data":{"content":"example","exampleKind":"usage"},"content":[
            {"tag":"span","style":{"color":"green","fontWeight":"bold"},"content":"▲"},
            {"tag":"ruby","content":["紙",{"tag":"rt","content":"かみ"}]},
            {"tag":"br"},
            {"tag":"img","path":"a.png"},
            {"tag":"a","href":"?query=紙","content":"紙"},
            {"tag":"a","href":"https://example.com/x?a=1&b=2","content":"link"}
          ]}
        ]}
        """#
        let html = styled(content)
        #expect(html.contains(#"<div class="gloss-sc-div" data-sc-content="example" data-sc-example-kind="usage">"#))
        #expect(html.contains(#"<span class="gloss-sc-span" style="color: green; font-weight: bold;">▲</span>"#))
        #expect(html.contains(#"<ruby class="gloss-sc-ruby">紙<rt class="gloss-sc-rt">かみ</rt></ruby><br>"#))
        #expect(!html.contains("img"))
        #expect(html.contains(#"<a class="gloss-sc-a">紙</a>"#))
        #expect(html.contains(#"<a class="gloss-sc-a" href="https://example.com/x?a=1&amp;b=2">link</a>"#))
    }

    @Test func aStyleValueCannotOpenAnotherDeclaration() {
        let html = styled(#"{"tag":"span","style":{"color":"red; position: fixed"},"content":"x"}"#)
        #expect(html.contains(#"<span class="gloss-sc-span">x</span>"#))
    }

    @Test func severalGlossariesBecomeAList() {
        let html = GlossaryHTML.styled(
            dictionary: "D",
            glossaries: [
                DictionaryLookupGlossary(dictionary: "D", content: "one"),
                DictionaryLookupGlossary(dictionary: "D", content: #"["two","three"]"#),
            ],
            style: ""
        )
        #expect(html.contains(#"<ol><li>one</li><li><ul class="glossary-list"><li>two</li><li>three</li></ul></li></ol>"#))
    }

    @Test func theStylesheetIsScopedToItsDictionary() {
        let css = """
        /* colours */
        .gloss-sc-span[data-sc-content="example"], div > b { color: #080; }
        @media (prefers-color-scheme: dark) { :root { color: white; } a:is(.x, .y) { color: cyan } }
        @import url("evil.css");
        @font-face { font-family: X; src: url(x.woff) }
        """
        let scoped = GlossaryHTML.scopedCSS(css, dictionary: #"A "B""#)
        let prefix = #".yomitan-glossary [data-dictionary="A \"B\""]"#
        #expect(scoped.contains(prefix + #" .gloss-sc-span[data-sc-content="example"], "# + prefix + " div > b { color: #080; }"))
        #expect(scoped.contains("@media (prefers-color-scheme: dark) { " + prefix + " { color: white; }\n" + prefix + " a:is(.x, .y) { color: cyan } }"))
        #expect(scoped.contains("@font-face { font-family: X; src: url(x.woff) }"))
        #expect(!scoped.contains("@import"))
        #expect(!scoped.contains("colours"))
    }

    @Test func aStylesheetCannotCloseItsStyleElement() {
        let scoped = GlossaryHTML.scopedCSS(#"b::after { content: "</style><script>" }"#, dictionary: "D")
        #expect(!scoped.contains("</style"))
    }

    @Test func noContentMeansNoField() {
        #expect(GlossaryHTML.styled(dictionary: "D", glossaries: [], style: "b{}") == "")
    }
}
