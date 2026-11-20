import CryptoKit
import Foundation

var failures = 0
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: Int = #line) {
    if a != b { failures += 1; print("FAIL line \(line): got \(a), expected \(b) \(msg)") }
}
func q(_ t: String, artist: String? = nil, channel: String? = nil) -> SongQuery {
    TitleCleaner.query(title: t, artist: artist, channel: channel)
}

// Title cleaning
eq(q("Taylor Swift - Love Story (Official Music Video)"), SongQuery(artist: "Taylor Swift", track: "Love Story"))
eq(q("Coldplay - Yellow (Official Video) [4K]"), SongQuery(artist: "Coldplay", track: "Yellow"))
eq(q("Queen – Bohemian Rhapsody (Remastered 2011)"), SongQuery(artist: "Queen", track: "Bohemian Rhapsody"))
eq(q("Adele - Hello | Official Video"), SongQuery(artist: "Adele", track: "Hello"))
eq(q("Artist - Song ft. Someone Else"), SongQuery(artist: "Artist", track: "Song"))
eq(q("Artist - Song (feat. Someone) (Lyrics)"), SongQuery(artist: "Artist", track: "Song"))
eq(q("Imagine", channel: "John Lennon - Topic"), SongQuery(artist: "John Lennon", track: "Imagine"))
eq(q("Shake It Off", channel: "TaylorSwiftVEVO"), SongQuery(artist: "Taylor Swift", track: "Shake It Off"))
eq(q("Blinding Lights", artist: "The Weeknd"), SongQuery(artist: "The Weeknd", track: "Blinding Lights"))
eq(q("(I Can't Get No) Satisfaction", artist: "The Rolling Stones"), SongQuery(artist: "The Rolling Stones", track: "(I Can't Get No) Satisfaction"))
eq(q("Video Killed the Radio Star", artist: "The Buggles"), SongQuery(artist: "The Buggles", track: "Video Killed the Radio Star"))
eq(q("No Artist Here"), SongQuery(artist: nil, track: "No Artist Here"))

// LRC parsing
let lines = LRC.parse("[ar:Someone]\n[00:01.50] one\n[00:03.00][00:09.25] two\n[01:00.00]\n")
eq(lines.map(\.time), [1.5, 3.0, 9.25, 60.0])
eq(lines.map(\.text), ["one", "two", "two", ""])
eq(LRC.currentIndex(in: lines, at: 0.5), nil)
eq(LRC.currentIndex(in: lines, at: 1.5), 0)
eq(LRC.currentIndex(in: lines, at: 5), 1)
eq(LRC.currentIndex(in: lines, at: 100), 3)

// Sync math: line noted at 1:00 is actually sung at 1:05 -> lyrics should show 5s later => shift -5
eq(SyncMath.shift(lineTime: 60, position: 65), -5.0)
eq(SyncMath.shift(lineTime: 60, position: 58.37), 1.65)   // rounds to 0.05

// Controller: click-to-fix persists per song and is restored by a new instance.
// Demo lyrics have lines at 0:02, 0:06, 0:10, 0:14 (indexes 0...3).
let tmp = NSTemporaryDirectory() + "lyrics-test-\(UUID().uuidString)"
setenv("LYRICS_DATA_DIR", tmp, 1)
do {
    let c = Controller()
    c.showDemo()
    c.clock.sync(position: 12, playing: false)
    eq(c.clock.currentIndex, 2)                    // at 0:12 (+0.3s lead) the 0:10 line is current
    c.syncLine(3)                                  // "the 0:14 line is being sung right now"
    eq(c.userOffset, 2.0)
    eq(c.clock.currentIndex, 3)                    // so it is now the current line
    c.nudge(-0.25)
    eq(c.userOffset, 1.75)
}
do {
    let c2 = Controller()                          // fresh instance = app restart
    c2.showDemo()
    eq(c2.userOffset, 1.75, "offset restored from disk")
    c2.clock.sync(position: 12, playing: false)
    eq(c2.clock.currentIndex, 3)
    c2.resetOffset()
    eq(c2.userOffset, 0.0)
}
do {
    let c3 = Controller(); c3.showDemo()
    eq(c3.userOffset, 0.0, "reset persisted")
}
let json = (try? String(contentsOfFile: tmp + "/sync-offsets.json")) ?? ""
eq(json.contains("\"demo\""), false, "zero offset removes the entry")
try? FileManager.default.removeItem(atPath: tmp)


// Versions
eq(Version("v0.2.0")! > Version("0.1.9")!, true)
eq(Version("1.10")! > Version("1.9")!, true, "numeric, not lexical")
eq(Version("1.0")! == Version("1.0.0")!, true)
eq(Version("0.1.0-beta")! == Version("0.1.0")!, true)
eq(Version("abc") == nil, true)
eq(Version("1.x") == nil, true)

// Release feed parsing (GitHub "latest release" shape)
func feed(tag: String = "v0.2.0", zip: String = "https://github.com/o/r/releases/download/v0.2.0/LyricsOverlay.zip",
          sig: String = "https://github.com/o/r/releases/download/v0.2.0/LyricsOverlay.zip.sig",
          draft: Bool = false, assets: Bool = true) -> Data {
    let a = assets ? "[{\"name\":\"LyricsOverlay.zip\",\"browser_download_url\":\"\(zip)\"},{\"name\":\"LyricsOverlay.zip.sig\",\"browser_download_url\":\"\(sig)\"}]" : "[]"
    return Data("{\"tag_name\":\"\(tag)\",\"body\":\"Notes\",\"draft\":\(draft),\"assets\":\(a)}".utf8)
}
let rel = ReleaseFeed.parse(feed())
eq(rel?.version.description, "0.2.0")
eq(rel?.notes, "Notes")
eq(ReleaseFeed.parse(feed(assets: false)) == nil, true, "needs both assets")
eq(ReleaseFeed.parse(feed(draft: true)) == nil, true, "drafts ignored")
eq(ReleaseFeed.parse(feed(tag: "nightly")) == nil, true, "non-version tag")
eq(ReleaseFeed.parse(feed(zip: "http://evil.example/LyricsOverlay.zip")) == nil, true, "plain http rejected")
eq(ReleaseFeed.parse(feed(zip: "http://127.0.0.1:9/LyricsOverlay.zip", sig: "http://127.0.0.1:9/a.sig")) == nil, true,
   "loopback http only allowed with a test feed override")
setenv("LYRICS_UPDATE_FEED", "http://127.0.0.1:9/latest.json", 1)
eq(ReleaseFeed.parse(feed(zip: "http://127.0.0.1:9/LyricsOverlay.zip", sig: "http://127.0.0.1:9/LyricsOverlay.zip.sig")) != nil, true)
eq(ReleaseFeed.parse(feed(zip: "http://evil.example/LyricsOverlay.zip", sig: "http://127.0.0.1:9/LyricsOverlay.zip.sig")) == nil, true,
   "non-loopback http still rejected under override")
unsetenv("LYRICS_UPDATE_FEED")

// Signatures
let signer = Curve25519.Signing.PrivateKey()
let pub = signer.publicKey.rawRepresentation.base64EncodedString()
let payload = Data("pretend this is LyricsOverlay.zip".utf8)
let goodSig = try! signer.signature(for: payload).base64EncodedString()
eq(UpdateVerifier.verify(payload, signatureBase64: goodSig, publicKeyBase64: pub), true)
eq(UpdateVerifier.verify(payload + Data([0]), signatureBase64: goodSig, publicKeyBase64: pub), false, "tampered download")
let other = try! Curve25519.Signing.PrivateKey().signature(for: payload).base64EncodedString()
eq(UpdateVerifier.verify(payload, signatureBase64: other, publicKeyBase64: pub), false, "signed by a different key")
eq(UpdateVerifier.verify(payload, signatureBase64: "not base64!!", publicKeyBase64: pub), false)
eq(UpdateVerifier.verify(payload, signatureBase64: goodSig), false, "a stranger's signature fails against the embedded key")


// Extension download (stubbed network)
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var reply: (Int, Data) = (200, Data())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        let (code, data) = Self.reply
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func blocking<T>(_ work: @escaping () async -> T) -> T {
    let sem = DispatchSemaphore(value: 0); var out: T!
    Task.detached { out = await work(); sem.signal() }
    sem.wait(); return out
}
let stubCfg = URLSessionConfiguration.ephemeral; stubCfg.protocolClasses = [StubProtocol.self]
let stubSession = URLSession(configuration: stubCfg)
let extDir = NSTemporaryDirectory() + "lyrics-ext-\(UUID().uuidString)"
setenv("LYRICS_DATA_DIR", extDir, 1)
let xpiURL = URL(string: "https://github.com/o/r/releases/latest/download/lyrics-overlay-bridge.xpi")!
let goodXPI = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 7, count: 400)

func fetch(_ code: Int, _ body: Data, url: URL = xpiURL) -> (URL?, String?) {
    StubProtocol.reply = (code, body)
    return blocking {
        do { return (try await ExtensionFile.download(from: url, session: stubSession), nil) }
        catch { return (nil, error.localizedDescription) }
    }
}

eq(ExtensionFile.isPlausible(goodXPI), true)
eq(ExtensionFile.isPlausible(Data("<html>Not Found</html>".utf8) + Data(repeating: 32, count: 300)), false, "html is not a zip")
eq(ExtensionFile.isPlausible(Data([0x50, 0x4B, 0x03, 0x04])), false, "too small")

let ok = fetch(200, goodXPI)
eq(ok.0?.lastPathComponent, "lyrics-overlay-bridge.xpi")
eq((try? Data(contentsOf: ExtensionFile.localURL)) == goodXPI, true, "saved bytes match")
eq(fetch(404, Data()).1?.contains("hasn't been published") ?? false, true, "404 explains it's not published")
eq(fetch(500, Data()).1?.contains("HTTP 500") ?? false, true)
eq(fetch(200, Data("<html>oops</html>".utf8) + Data(repeating: 32, count: 300)).1?.contains("isn't a valid") ?? false, true)
eq((try? Data(contentsOf: ExtensionFile.localURL)) == goodXPI, true, "a bad download never overwrites a good saved copy")
eq(fetch(200, goodXPI, url: URL(string: "http://evil.example/x.xpi")!).1?.contains("Refusing") ?? false, true, "plain http refused")
try? FileManager.default.removeItem(atPath: extDir)

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
