import Foundation

enum AnkiJSInjectedScript {
    static func source(handlerName: String) -> String {
        """
        /*
         * Amgi Anki JS API
         * Compatibility source: AnkiDroid JavaScript API
         * Version: \(AnkiJSBridge.apiVersion)
         */
        const jsApiList = {
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
            ankiIsInNightMode: "isInNightMode",
            ankiIsDisplayingAnswer: "isDisplayingAnswer",
            ankiGetDeckName: "deckName",
            ankiTtsFieldModifierIsAvailable: "ttsFieldModifierIsAvailable",
            ankiTtsIsSpeaking: "ttsIsSpeaking",
            ankiTtsStop: "ttsStop",
            ankiBuryCard: "buryCard",
            ankiBuryNote: "buryNote",
            ankiSuspendCard: "suspendCard",
            ankiSuspendNote: "suspendNote",
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
            ankiShowAnswer: "showAnswer",
            ankiShowToast: "showToast",
            ankiAnswerEase1: "answerEase1",
            ankiAnswerEase2: "answerEase2",
            ankiAnswerEase3: "answerEase3",
            ankiAnswerEase4: "answerEase4",
            ankiAddTagToCard: "addTagToCard",
            ankiAddTagToNote: "addTagToNote",
            ankiSetNoteTags: "setNoteTags",
            ankiGetNoteTags: "getNoteTags",
        };

        class AnkiDroidJS {
            constructor({ developer, version }) {
                this.developer = developer;
                this.version = version;
                this.handleRequest("init");
            }

            static init({ developer, version }) {
                return new AnkiDroidJS({ developer, version });
            }

            handleRequest = async (endpoint, data) => {
                const handler = window.webkit?.messageHandlers?.\(handlerName);
                if (!handler || typeof handler.postMessage !== "function") {
                    throw new Error("Anki JS API native bridge is unavailable");
                }

                const responseData = await handler.postMessage({
                    endpoint,
                    developer: this.developer,
                    version: this.version,
                    data,
                });

                if (endpoint.includes("nextTime") || endpoint.includes("deckName")) {
                    return responseData;
                }
                return JSON.parse(responseData);
            };
        }

        Object.keys(jsApiList).forEach(method => {
            if (method === "ankiAddTagToNote") {
                AnkiDroidJS.prototype[method] = async function (noteId, tag) {
                    console.warn("ankiAddTagToNote is deprecated. Use ankiSetNoteTags instead");
                    return await this.handleRequest(
                        jsApiList[method],
                        JSON.stringify({ noteId, tag })
                    );
                };
                return;
            }

            if (method === "ankiSetNoteTags") {
                AnkiDroidJS.prototype[method] = async function (tags) {
                    let hasSpaces = false;
                    const normalized = Array.isArray(tags) ? tags.slice() : [];
                    for (let index = 0; index < normalized.length; index += 1) {
                        normalized[index] = String(normalized[index] ?? "").trim();
                        if (normalized[index].includes(" ") || normalized[index].includes("　")) {
                            normalized[index] = normalized[index].replace(/ |　/g, "_");
                            hasSpaces = true;
                        }
                    }
                    if (hasSpaces) {
                        console.warn("Spaces in tags have been converted to underscores");
                    }
                    return await this.handleRequest(
                        jsApiList[method],
                        JSON.stringify({ tags: normalized })
                    );
                };
                return;
            }

            if (method === "ankiTtsSpeak") {
                AnkiDroidJS.prototype[method] = async function (text, queueMode = 0) {
                    return await this.handleRequest(
                        jsApiList[method],
                        JSON.stringify({ text, queueMode })
                    );
                };
                return;
            }

            if (method === "ankiShowToast") {
                AnkiDroidJS.prototype[method] = async function (text, shortLength = true) {
                    return await this.handleRequest(
                        jsApiList[method],
                        JSON.stringify({ text, shortLength })
                    );
                };
                return;
            }

            if (method === "ankiShowAnswer") {
                AnkiDroidJS.prototype[method] = async function () {
                    const typedAnswer = typeof window.amgiGetTypedAnswer === "function"
                        ? window.amgiGetTypedAnswer()
                        : null;
                    return await this.handleRequest(
                        jsApiList[method],
                        JSON.stringify({ typedAnswer })
                    );
                };
                return;
            }

            if (method === "ankiAnswerEase1" || method === "ankiAnswerEase2" || method === "ankiAnswerEase3" || method === "ankiAnswerEase4") {
                AnkiDroidJS.prototype[method] = async function () {
                    const typedAnswer = typeof window.amgiGetTypedAnswer === "function"
                        ? window.amgiGetTypedAnswer()
                        : null;
                    return await this.handleRequest(
                        jsApiList[method],
                        JSON.stringify({ typedAnswer })
                    );
                };
                return;
            }

            AnkiDroidJS.prototype[method] = async function (data) {
                return await this.handleRequest(jsApiList[method], data);
            };
        });

        globalThis.AnkiDroidJS = AnkiDroidJS;
        window.AnkiDroidJS = AnkiDroidJS;
        globalThis.AnkiJS = AnkiDroidJS;
        window.AnkiJS = AnkiDroidJS;
        """
    }
}
