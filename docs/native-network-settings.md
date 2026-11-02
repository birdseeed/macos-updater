# Native Network settings source milestone

PAT-2666 supplies settings retained by the app session and an explicit descriptive native
observation adapter. Transport and secure credentials remain separate unfinished
work. The existing synthetic policy, refusing ordinary entry points, original
205 assertions and fixture pins are unchanged. A settings choice grants no
connection, dispatch, update or installation authority.

## Session controls

The app owns one `NativeClientSession` in `@StateObject`, shared by its
`WindowGroup` and `MenuBarExtra`. It survives closing the last window; closing
a window alone does not release the shared session. The
`NativeNetworkSettingsController.native()` belongs to that shared app session,
so its choice and drafts are retained for the app session. Separately constructed
app sessions have separate owners; that does not prove per-window isolation.
The private ordinary constructor creates only an inert provider. Construction,
app startup, rendering, navigation, draft edits and Apply perform no platform
reads, background work, timers or persistence. The view has bound
system/direct/manual controls, manual host/port
fields, Apply, Refresh and Cancel. It uses system fonts and literal text.

Apply uses only `NetworkConfiguration.validate()` for syntactic host and port
validation, then retains a `NativeNetworkChoice` for future in-app networking in
the app session. Manual ports use ASCII digits and range 1 through 65535. Draft
storage is bounded; invalid endpoints produce finite guidance without copying
host, credentials or raw errors into status. Editing clears the accepted choice,
clears manual fields when switching to system/direct, advances a saturating
revision and invalidates/cancels any pending request. Request identity also fences
callbacks independently of the revision, including at saturation.

Settled observations remain descriptive after edits and always say
“Last explicit refresh; may have changed”. PAC, discovery/WPAD, SOCKS or invalid
system snapshots block applying system mode until a fresh supported observation
replaces them. There is no automatic direct fallback. No configured proxy does
not establish destination routing: exceptions may still apply. An available path
does not establish Internet or service reachability. Status explicitly says
“No network transport connected yet”.

## Explicit bounded native observation

Only explicit Refresh calls the provider. It creates a request-owned
`NWPathMonitor` and schedules a two second timeout on a private serial queue.
The first path callback is classified to a finite enum and cancels the monitor.
A separate utility queue performs `CFNetworkCopySystemProxySettings()` and
consumes its retained copy read-only. The copied dictionary is classified using
the same `NativeNetworkProxySnapshot.classify` parser exposed to independent
Testing SPI checks. Raw dictionaries never cross the queue boundary or enter
status, logs or persistence. Only finite proxy values leave the copy closure.
No DNS, PAC evaluation/download, connection request or system proxy write exists.

The parser bounds dictionary entries and enabled endpoints. Enable flags accept
only integer CFNumbers equal to zero or one, excluding CFBoolean, floating
numbers, strings and other coercions. Enabled HTTP/HTTPS endpoints pass through
the existing syntactic validator. PAC, discovery and SOCKS take precedence over
HTTP/HTTPS. Any `__SCOPED__` entry refuses conservatively. Disabled protocol payloads
and unrelated metadata are inert. Proxy hosts, users, credentials, PAC URLs and
raw errors never appear in the descriptive result.

A request settles once when both first path and proxy results arrive, or when
the timeout supplies unknown for missing facts. Settlement and cancellation
cancel the monitor and timer and release the completion. CFNetwork's synchronous
OS copy cannot be forcibly interrupted if the OS blocks; it runs off the main
actor so the timeout can settle independently. Queue scheduling and main-actor
callback delivery are cooperative, not a hard two second kernel wall-clock
promise. A cancelled copy may finish later, but its result is discarded.

The controller sets its pending identity before `begin`, supports synchronous
completion and reentrant actions, and clears authority before cancelling. Every
returned request is cancelled once by the controller, including a request
returned after synchronous settlement. Duplicate, cancelled, pre-edit and older
callbacks cannot publish. Provider completion captures the controller weakly;
the native worker clears callbacks and platform resources on completion/cancel.
When the controller is released with a pending request, its `RequestCleanup`
holder schedules cancellation on the main queue. Closing a window alone does not
release the shared controller. Native request destruction also releases its
worker asynchronously.
Cancellation cannot undo a callback already queued for delivery, so controller
identity/revision checks remain necessary.

## Proof boundaries

The Testing SPI provider constructor always labels observations “Test double”.
Its injected finite values grant no native or transport authority. Independent
checks exercise fake requests synchronously; offscreen view checks paint the
actual retained view and examine binding/source contracts. Neither executes the
native APIs or proves installed behaviour. The native factory is deliberately
idle during ordinary creation and rendering, including in those checks.

Injected-provider and offscreen checks do not establish actual native
observation, installed behaviour or release readiness. Parent verification,
whole-diff independent review, CI and source acceptance are recorded separately.
A source milestone cannot close the unfinished transport and credential scope
or establish installed update readiness.

## Primary Apple references for implementation

- [URLSessionConfiguration.connectionProxyDictionary](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/connectionproxydictionary):
  nil uses system proxy settings. This future transport default is distinct from
  the descriptive system snapshot and grants no connection authority here.
- [CFNetworkCopySystemProxySettings](https://developer.apple.com/documentation/cfnetwork/cfnetworkcopysystemproxysettings()):
  explicit Refresh may copy the current system proxy dictionary read-only.
  Treat enabled automatic proxy configuration/discovery as unsupported rather
  than resolving or downloading a PAC script.
- [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
  and [cancel()](https://developer.apple.com/documentation/network/nwpathmonitor/cancel()):
  use a bounded one-shot monitor only on explicit Refresh and cancel on every
  result, timeout and controller cancellation. Path status is observational.

These links are implementation references, not a claim of executed native proof.
