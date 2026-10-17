import Foundation
import Testing
@testable import DecantCore

let escapedSample = #"{\"identifier\":\"WELCOMEBACK26\",\"amount\":150,\"validFrom\":\"2026-09-01\",\"validUntil\":\"2027-08-31\",\"durationInMonths\":\"2\",\"paymentAfterMonths\":\"2\",\"disbursementType\":\"onetime\"}"#

let escapedExpected = """
{
  "identifier": "WELCOMEBACK26",
  "amount": 150,
  "validFrom": "2026-09-01",
  "validUntil": "2027-08-31",
  "durationInMonths": "2",
  "paymentAfterMonths": "2",
  "disbursementType": "onetime"
}
"""

let base64Sample = "eyJwbGFuIjoidGVhbSIsInNlYXRzIjoxMiwicmVuZXdzQXQiOiIyMDI3LTAxLTAxIiwib3duZXIiOiJtLmtyYXVzIn0="

let base64Expected = """
{
  "plan": "team",
  "seats": 12,
  "renewsAt": "2027-01-01",
  "owner": "m.kraus"
}
"""

let tsSample = #"export async function redeem(code:string,userId:string){const voucher=await db.vouchers.findOne({identifier:code});if(!voucher||voucher.validUntil<new Date())throw new Error("Voucher expired");return applyCredit(userId,voucher.amount)}"#

let tsExpected = """
export async function redeem(code: string, userId: string) {
  const voucher = await db.vouchers.findOne({ identifier: code });
  if (!voucher || voucher.validUntil < new Date())
    throw new Error("Voucher expired");
  return applyCredit(userId, voucher.amount);
}
"""

@Test func escapedJSONBecomesCleanJSON() throws {
    let r = try #require(Engine.convert(escapedSample))
    #expect(r.input == .escapedJSON)
    #expect(r.output == .json)
    #expect(r.text == escapedExpected)
    #expect(r.title == "WELCOMEBACK26")
    #expect(r.details.contains(Detail("Escapes removed", "26")))
    #expect(r.details.contains(Detail("Keys", "7")))
    #expect(r.summary == "9 lines · 2 spaces · UTF-8")
    #expect(r.meta == ["7 keys", "26 escapes removed"])
}

@Test func quotedEscapedJSONString() throws {
    let r = try #require(Engine.convert(#""{\"a\":1}""#))
    #expect(r.input == .escapedJSON)
    #expect(r.text == "{\n  \"a\": 1\n}")
}

@Test func base64ChainsToJSON() throws {
    let r = try #require(Engine.convert(base64Sample))
    #expect(r.input == .base64)
    #expect(r.output == .json)
    #expect(r.text == base64Expected)
    #expect(r.steps.map(\.label) == ["Decoded", "Parsed as JSON", "Formatted"])
    #expect(r.summary == "92 characters → 68 bytes · UTF-8")
    #expect(r.meta == ["68 bytes · UTF-8", "Standard alphabet, padded"])
}

@Test func base64WithoutNestingGivesText() throws {
    var o = Options()
    o.decodeNested = false
    let r = try #require(Engine.convert(base64Sample, options: o))
    #expect(r.output == .text)
    #expect(r.text == #"{"plan":"team","seats":12,"renewsAt":"2027-01-01","owner":"m.kraus"}"#)
}

@Test func typeScriptIsFormatted() throws {
    let r = try #require(Engine.convert(tsSample))
    #expect(r.input == .typescript)
    #expect(r.text == tsExpected)
    #expect(r.error == nil)
    #expect(r.summary == "1 line → 6 lines · 2 spaces · UTF-8")
    #expect(r.title == "redeem()")
    #expect(r.meta == ["1 → 6 lines", "235 characters"])
}

@Test func javaScriptBlocksAndCallbacks() {
    let out = JSFormatter.format("const xs=[1,2].map(x=>{return x*2});if(a){b()}else{c()}", indent: "  ").text
    #expect(out == """
    const xs = [1, 2].map(x => {
      return x * 2;
    });
    if (a) {
      b();
    } else {
      c();
    }
    """)
}

@Test func unixSecondsAndMilliseconds() throws {
    var o = Options()
    o.timeZone = TimeZone(identifier: "Europe/Berlin")!
    for input in ["1792249669", "1792249669000"] {
        let r = try #require(Engine.convert(input, options: o))
        #expect(r.input == .unixTime)
        #expect(r.text.contains("ISO 8601      2026-10-17T15:07:49Z"))
        #expect(r.text.contains("Local         Sat, 17 Oct 2026, 17:07:49"))
        #expect(r.text.contains("UTC           Sat, 17 Oct 2026 15:07:49"))
    }
}

@Test func jsonMinifyAndSortKeys() throws {
    var o = Options()
    o.minify = true
    o.sortKeys = true
    let r = try #require(Engine.convert(#"{ "b": [1, {"d": null, "c": true}], "a": "x\ny" }"#, options: o))
    #expect(r.text == #"{"a":"x\ny","b":[1,{"c":true,"d":null}]}"#)
}

@Test func unicodeEscapesRoundTrip() throws {
    let r = try #require(Engine.convert(#"{"e":"é😀"}"#))
    #expect(r.text == "{\n  \"e\": \"é😀\"\n}")
}

@Test func invalidJSONReportsPosition() throws {
    let r = try #require(Engine.convert("{\"a\": }"))
    #expect(r.error == "Unexpected character at line 1, column 7")
}

@Test func plainTextIsNotDetected() {
    #expect(Engine.convert("hello world") == nil)
    #expect(Engine.convert("password") == nil)
    #expect(Engine.convert("42") == nil)
}

@Test func convertTargets() throws {
    let r = try #require(Engine.convert(#"{"a":"b"}"#))
    #expect(Engine.apply(.escapedString, to: r) == #"{\"a\":\"b\"}"#)
    #expect(Engine.apply(.base64, to: r) == "eyJhIjoiYiJ9")
    #expect(Engine.apply(.hex, to: r).hasPrefix("7b22"))
}

@Test func forcedBase64EncodesPlainText() throws {
    let r = try #require(Engine.convert("hello", force: .base64))
    #expect(r.output == .base64)
    #expect(r.text == "aGVsbG8=")
}
