//
//  AnkiDroidJSShim.swift
//  ReviewFeature
//

import Foundation

/// The page side of the AnkiDroid-compatible card API: a global
/// `AnkiDroidJS` class with the same methods, arguments and promise results
/// as AnkiDroid's `js-api.js` (API version 0.0.3), so card templates written
/// for AnkiDroid run unchanged.
///
/// AnkiDroid's shim POSTs to `/jsapi/<endpoint>` and gets back the JSON text
/// of `{success, value}`. Here every call goes through one
/// `amgiAnkiDroidJS` message handler with a reply; the native side answers
/// with that same JSON text, so the parsing below — including AnkiDroid's
/// quirk of handing `nextTime*` and `deckName` back unparsed — matches.
enum AnkiDroidJSShim {
    static let handlerName = "amgiAnkiDroidJS"

    static let source = #"""
(function () {
    if (window.AnkiDroidJS) { return; }

    var jsApiList = {
        ankiGetNewCardCount: "newCardCount",
        ankiGetLrnCardCount: "lrnCardCount",
        ankiGetRevCardCount: "revCardCount",
        ankiGetETA: "eta",
        ankiGetCardMark: "cardMark",
        ankiGetCardFlag: "cardFlag",
        ankiGetNextTime1: "nextTime1",
        ankiGetNextTime2: "nextTime2",
        ankiGetNextTime3: "nextTime3",
        ankiGetNextTime4: "nextTime4",
        ankiGetCardReps: "cardReps",
        ankiGetCardInterval: "cardInterval",
        ankiGetCardFactor: "cardFactor",
        ankiGetCardMod: "cardMod",
        ankiGetCardId: "cardId",
        ankiGetCardNid: "cardNid",
        ankiGetCardType: "cardType",
        ankiGetCardDid: "cardDid",
        ankiGetCardLeft: "cardLeft",
        ankiGetCardODid: "cardODid",
        ankiGetCardODue: "cardODue",
        ankiGetCardQueue: "cardQueue",
        ankiGetCardLapses: "cardLapses",
        ankiGetCardDue: "cardDue",
        ankiIsInFullscreen: "isInFullscreen",
        ankiSetFullscreenButtonsAndMenu: "setFullscreenButtonsAndMenu",
        ankiSetFullscreenButtonsOnly: "setFullscreenButtonsOnly",
        ankiSetFullscreenAllGone: "setFullscreenAllGone",
        ankiIsTopbarShown: "isTopbarShown",
        ankiIsInNightMode: "isInNightMode",
        ankiIsDisplayingAnswer: "isDisplayingAnswer",
        ankiGetDeckName: "deckName",
        ankiIsActiveNetworkMetered: "isActiveNetworkMetered",
        ankiTtsFieldModifierIsAvailable: "ttsFieldModifierIsAvailable",
        ankiTtsIsSpeaking: "ttsIsSpeaking",
        ankiTtsStop: "ttsStop",
        ankiBuryCard: "buryCard",
        ankiBuryNote: "buryNote",
        ankiSuspendCard: "suspendCard",
        ankiSuspendNote: "suspendNote",
        ankiAddTagToCard: "addTagToCard",
        ankiResetProgress: "resetProgress",
        ankiMarkCard: "markCard",
        ankiToggleFlag: "toggleFlag",
        ankiSearchCard: "searchCard",
        ankiSearchCardWithCallback: "searchCardWithCallback",
        ankiTtsSpeak: "ttsSpeak",
        ankiTtsSetLanguage: "ttsSetLanguage",
        ankiTtsSetPitch: "ttsSetPitch",
        ankiTtsSetSpeechRate: "ttsSetSpeechRate",
        ankiEnableHorizontalScrollbar: "enableHorizontalScrollbar",
        ankiEnableVerticalScrollbar: "enableVerticalScrollbar",
        ankiSetCardDue: "setCardDue",
        ankiShowNavigationDrawer: "showNavigationDrawer",
        ankiShowOptionsMenu: "showOptionsMenu",
        ankiShowToast: "showToast",
        ankiShowAnswer: "showAnswer",
        ankiAnswerEase1: "answerEase1",
        ankiAnswerEase2: "answerEase2",
        ankiAnswerEase3: "answerEase3",
        ankiAnswerEase4: "answerEase4",
        ankiSttSetLanguage: "sttSetLanguage",
        ankiSttStart: "sttStart",
        ankiSttStop: "sttStop",
        ankiAddTagToNote: "addTagToNote",
        ankiSetNoteTags: "setNoteTags",
        ankiGetNoteTags: "getNoteTags"
    };

    function AnkiDroidJS(contract) {
        contract = contract || {};
        this.developer = contract.developer;
        this.version = contract.version;
        this.handleRequest("init").catch(function () {});
    }

    AnkiDroidJS.init = function (contract) { return new AnkiDroidJS(contract); };

    AnkiDroidJS.prototype.handleRequest = function (endpoint, data) {
        var handler = window.webkit && window.webkit.messageHandlers
            && window.webkit.messageHandlers.__HANDLER__;
        if (!handler) { return Promise.reject(new Error("Failed to make the request")); }
        return handler.postMessage({
            endpoint: endpoint,
            developer: this.developer == null ? "" : String(this.developer),
            version: this.version == null ? "" : String(this.version),
            data: data === undefined ? null : data
        }).then(function (responseData) {
            if (endpoint.indexOf("nextTime") !== -1 || endpoint.indexOf("deckName") !== -1) {
                return responseData;
            }
            return JSON.parse(responseData);
        }, function (error) {
            console.error("Request error:", error);
            throw error;
        });
    };

    Object.keys(jsApiList).forEach(function (method) {
        var endpoint = jsApiList[method];
        var call;
        if (method === "ankiAddTagToNote") {
            call = function (noteId, tag) {
                console.warn("ankiAddTagToNote is deprecated. Use ankiSetNoteTags instead");
                return this.handleRequest(endpoint, JSON.stringify({ noteId: noteId, tag: tag }));
            };
        } else if (method === "ankiSetNoteTags") {
            call = function (tags) {
                var hasSpaces = false;
                for (var i = 0; i < tags.length; i++) {
                    tags[i] = tags[i].trim();
                    if (tags[i].includes(" ") || tags[i].includes("　")) {
                        tags[i] = tags[i].replace(" ", "_").replace("　", "_");
                        hasSpaces = true;
                    }
                }
                if (hasSpaces) { console.warn("Spaces in tags have been converted to underscores"); }
                return this.handleRequest(endpoint, JSON.stringify({ tags: tags }));
            };
        } else if (method === "ankiTtsSpeak") {
            call = function (text, queueMode) {
                return this.handleRequest(endpoint, JSON.stringify({ text: text, queueMode: queueMode === undefined ? 0 : queueMode }));
            };
        } else if (method === "ankiShowToast") {
            call = function (text, shortLength) {
                return this.handleRequest(endpoint, JSON.stringify({ text: text, shortLength: shortLength === undefined ? true : shortLength }));
            };
        } else if (method === "ankiSearchCardWithCallback") {
            call = function (data) {
                return this.handleRequest(endpoint, data).then(function (response) {
                    if (response && Array.isArray(response.results)) {
                        var results = response.results;
                        delete response.results;
                        if (typeof window.ankiSearchCard === "function") {
                            window.ankiSearchCard(JSON.stringify(results));
                        }
                    }
                    return response;
                });
            };
        } else {
            call = function (data) { return this.handleRequest(endpoint, data); };
        }
        AnkiDroidJS.prototype[method] = call;
    });

    // AnkiDroid's card page has `addHook("ankiSearchCard", fn)` and a global
    // `ankiSearchCard(json)` that runs the hooks; cards written for it test
    // for `addHook` before using the search callback.
    var searchCardHooks = [];
    if (typeof window.addHook !== "function") {
        window.addHook = function (name, fn) {
            if (name !== "ankiSearchCard" || typeof fn !== "function") { return; }
            // This page outlives a card, so the next card's script hooks
            // again: replace the copy it left rather than run both.
            var source = String(fn);
            for (var i = 0; i < searchCardHooks.length; i++) {
                if (String(searchCardHooks[i]) === source) { searchCardHooks[i] = fn; return; }
            }
            searchCardHooks.push(fn);
        };
    }
    if (typeof window.ankiSearchCard !== "function") {
        window.ankiSearchCard = function (result) {
            result = JSON.parse(result);
            for (var i = 0; i < searchCardHooks.length; i++) { searchCardHooks[i](result); }
        };
    }

    window.AnkiDroidJS = AnkiDroidJS;
    globalThis.AnkiDroidJS = AnkiDroidJS;
})();
"""#.replacingOccurrences(of: "__HANDLER__", with: handlerName)
}
