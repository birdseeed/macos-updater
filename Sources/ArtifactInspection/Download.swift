import Foundation
import Darwin

func validateDownload(hops: [String], pin: TargetPin, receivedBytes: Int64,
                      elapsedSeconds: Double, limits: InspectionLimits) throws {
    guard FirefoxTargets.pins.contains(pin) else { throw InspectionFailure.unknownTarget }
    guard !hops.isEmpty, hops.first == pin.url else { throw InspectionFailure.unsafeURL }
    for raw in hops {
        guard raw.utf8.allSatisfy({ $0 > 32 && $0 < 127 }), !raw.contains("\\"),
              let url = URLComponents(string: raw), url.scheme == "https", url.host == "archive.mozilla.org",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.string == raw, raw.hasPrefix("https://archive.mozilla.org/") else { throw InspectionFailure.unsafeURL }
        let path = url.percentEncodedPath
        let remaining = path.replacingOccurrences(of: "%20", with: " ")
        guard !remaining.contains("%"), !path.contains("//"), path.hasPrefix("/"),
              !remaining.split(separator: "/", omittingEmptySubsequences: false).dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw InspectionFailure.unsafeURL
        }
    }
    guard limits.redirects >= 0, limits.redirects <= 3, hops.count - 1 <= limits.redirects else { throw InspectionFailure.redirectLimit }
    try ArtifactSizePolicy.validateExpectedLength(pin.byteLength)
    guard limits.downloadSeconds.isFinite, limits.downloadSeconds > 0, limits.downloadSeconds <= 180,
          limits.downloadBytes > 0, limits.downloadBytes <= ArtifactSizePolicy.absoluteMaximumBytes,
          receivedBytes >= 0, receivedBytes <= min(limits.downloadBytes, pin.byteLength),
          elapsedSeconds.isFinite, elapsedSeconds >= 0, elapsedSeconds <= limits.downloadSeconds else { throw InspectionFailure.downloadLimit }
}

struct DownloadObservation: Codable, Sendable {
    let sourceURL: String
    let redirectChain: [String]
    let receivedBytes: Int64
}

// URLSession callbacks use one delegate queue. The lock also protects the
// synchronous caller's snapshot and writer settlement. Closing under this lock
// invalidates the writer before any late callback can observe a recycled fd.
private final class DownloadReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let pin: TargetPin; let writer: StagedImageWriter; let limits = InspectionLimits()
    let completion = DispatchSemaphore(value: 0); let lock = NSLock()
    var hops: [String]; var bytes: Int64 = 0; var refusal: InspectionFailure?
    let started = DispatchTime.now().uptimeNanoseconds
    init(pin: TargetPin, writer: StagedImageWriter) { self.pin = pin; self.writer = writer; self.hops = [pin.url] }
    func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); defer { lock.unlock() }
        do {
            guard let location = response.value(forHTTPHeaderField: "Location"),
                  let next = request.url?.absoluteString, location == next else { throw InspectionFailure.unsafeURL }
            try validateDownload(hops: hops + [next], pin: pin, receivedBytes: bytes, elapsedSeconds: elapsed(), limits: limits)
            hops.append(next); completionHandler(request)
        } catch {
            refusal = error as? InspectionFailure ?? .unsafeURL; completionHandler(nil); task.cancel()
        }
    }
    // Both the delegate and the offline fixture drive these exact methods.
    // Target/redirect authorisation stays in the ordinary network entry point.
    func acceptResponse(statusCode: Int, url: String?, declaredLength: Int64, encoding: String?) throws {
        try ArtifactSizePolicy.validateExpectedLength(pin.byteLength)
        guard statusCode == 200, url == hops.last, declaredLength == pin.byteLength,
              encoding.map({ $0.lowercased() == "identity" }) ?? true else { throw InspectionFailure.downloadLimit }
    }
    func acceptChunk(_ data: Data) throws {
        guard elapsed() <= limits.downloadSeconds else { throw InspectionFailure.downloadLimit }
        let total = try ArtifactSizePolicy.adding(Int64(data.count), to: bytes, expectedLength: pin.byteLength)
        guard total <= limits.downloadBytes else { throw InspectionFailure.downloadLimit }
        try writer.write(data)
        bytes = total
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); defer { lock.unlock() }
        do {
            if let refusal { throw refusal }
            guard let response = response as? HTTPURLResponse else { throw InspectionFailure.downloadLimit }
            try acceptResponse(statusCode: response.statusCode, url: response.url?.absoluteString,
                               declaredLength: response.expectedContentLength,
                               encoding: response.value(forHTTPHeaderField: "Content-Encoding"))
            completionHandler(.allow)
        } catch {
            refusal = refusal ?? (error as? InspectionFailure ?? .downloadLimit)
            completionHandler(.cancel)
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard refusal == nil else { dataTask.cancel(); return }
        do { try acceptChunk(data) }
        catch { refusal = error as? InspectionFailure ?? .downloadLimit; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if error != nil { refusal = refusal ?? .downloadLimit }
        lock.unlock(); completion.signal()
    }
    func result(sealWriter: Bool = false) throws -> DownloadObservation {
        lock.lock(); defer { lock.unlock() }
        if let refusal { throw refusal }
        try ArtifactSizePolicy.validateComplete(receivedBytes: bytes, expectedLength: pin.byteLength)
        if sealWriter { try writer.sync() }
        return DownloadObservation(sourceURL: pin.url, redirectChain: hops, receivedBytes: bytes)
    }
    func finishImage(directory: Int32) throws -> VerifiedImage {
        lock.lock(); defer { lock.unlock() }
        if let refusal { throw refusal }
        try ArtifactSizePolicy.validateComplete(receivedBytes: bytes, expectedLength: pin.byteLength)
        return try writer.finish(directory: directory, pin: pin)
    }
    func closeWriter() {
        lock.lock(); defer { lock.unlock() }
        writer.closeWriter()
    }

}
func downloadImage(pin: TargetPin, workspace: String) throws -> (VerifiedImage, DownloadObservation) {
    try validateDownload(hops: [pin.url], pin: pin, receivedBytes: 0, elapsedSeconds: 0, limits: .init())
    let directory = try SafeFiles.privateDirectory(workspace); defer { close(directory) }
    try SafeFiles.preflight(directory, length: pin.byteLength)
    let receiver = DownloadReceiver(pin: pin, writer: try StagedImageWriter(directory: directory))
    defer { receiver.closeWriter() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false; configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 180
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
    let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: queue)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: URL(string: pin.url)!)
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    session.dataTask(with: request).resume()
    guard receiver.completion.wait(timeout: .now() + 180) == .success else {
        session.invalidateAndCancel(); throw InspectionFailure.downloadLimit
    }
    let observation = try receiver.result()
    let image = try receiver.finishImage(directory: directory)
    return (image, observation)
}

// No URLSession is constructed in this Testing SPI adapter. It feeds the ordinary
// receiver's exact header/chunk/finalisation methods and ordinary descriptor hash.
// It does not enter downloadImage(), expand its allowlist or construct OS evidence.
func downloadFixture(pin: TargetPin, declaredLength: Int64, chunks: [Data],
                     workspace: String, availableBytes: Int64?) throws -> String {
    let directory = try SafeFiles.privateDirectory(workspace); defer { close(directory) }
    try SafeFiles.preflight(directory, length: pin.byteLength, capacity: { _ in availableBytes })
    let receiver = DownloadReceiver(pin: pin, writer: try StagedImageWriter(directory: directory))
    defer { receiver.closeWriter() }
    try receiver.acceptResponse(statusCode: 200, url: pin.url, declaredLength: declaredLength, encoding: "identity")
    for chunk in chunks { try receiver.acceptChunk(chunk) }
    _ = try receiver.result(sealWriter: true)
    let path = workspace + "/artifact.dmg"
    try ArtifactBytes.verify(path: path, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
    return path
}

// Fixture delivery uses the same receiver, writable-owner settlement and retained
// reader factory as the network route; it never constructs a URLSession.
func downloadImageFixture(pin: TargetPin, chunks: [Data], workspace: String) throws -> VerifiedImage {
    let directory = try SafeFiles.privateDirectory(workspace); defer { close(directory) }
    try SafeFiles.preflight(directory, length: pin.byteLength)
    let receiver = DownloadReceiver(pin: pin, writer: try StagedImageWriter(directory: directory))
    defer { receiver.closeWriter() }
    try receiver.acceptResponse(statusCode: 200, url: pin.url, declaredLength: pin.byteLength, encoding: "identity")
    for chunk in chunks { try receiver.acceptChunk(chunk) }
    return try receiver.finishImage(directory: directory)
}
