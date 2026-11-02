# Controlled network probe source API

`NativeNetworkConnectionProbe(settings:)` retains one `NativeNetworkSettingsController`.
A caller must explicitly invoke `start(url:completion:)` after applying a choice.
Construction, reads, edits, Apply and refresh do not start transport. The app's
explicit DEBUG-only development selector composes one shared retained probe owner
into setup and Settings; only Test starts a bounded controlled local action and
displays its finite result. Ordinary and release app construction remain
unconfigured and inert. The existing descriptive settings text is unchanged.
`isRunning` reports one pending action; `cancel()` settles it once.

Only literal `http://127.0.0.1:<port>/probe` and
`http://[::1]:<port>/probe` endpoints are accepted, with an explicit port from
1 to 65535. Aliases, credentials, encoded paths, queries, fragments and redirects
refuse. Each action sends one GET within a five-second deadline and counts and
discards at most 65536 response body bytes. Authentication challenges and HTTP
401/407 refuse without a credential attempt.

Direct mode uses a new ephemeral URLSession with proxy types explicitly disabled,
no shared cache, cookie or credential storage, and no redirect follow-up.
System mode copies current CFNetwork settings at each action, off the main actor
within the same deadline; only a current unscoped configuration classified as
having no configured proxy is supported. Configured proxies, PAC, discovery,
SOCKS, invalid and unknown settings refuse without evaluation or direct fallback.

Manual HTTP mode accepts only an applied unauthenticated HTTP proxy with the exact
host `127.0.0.1` and port from 1 to 65535, on macOS 14 or later. Other proxy hosts
and older systems refuse `unsupportedProxy` before transport; the settings draft
validator retains its broader descriptive scope. The deployment target remains
macOS 13 for the other supported modes.

The manual candidate creates one numeric AF_INET TCP socket to that selected
loopback proxy port. It uses no URLSession proxy selection, hostname resolution,
origin socket, alternate destination or retry. The accepted original URL is used
only in the absolute-form GET request text; Host retains its exact authority,
including IPv6 brackets and explicit port. The request adds `Connection: close`
and `Accept-Encoding: identity`, with no cookie, authorisation or CONNECT request.
The nonblocking socket has close-on-exec and Darwin suppression of SIGPIPE set
before I/O. Setup, connect, partial writes and reads share the worker's serial
queue and five-second timer. Readiness callbacks have finite syscall and byte
budgets. Writable readiness is cancelled after the request, and the shared
socket closes exactly once after both readiness sources have quiesced.

The manual response parser supports a finite HTTP/1.1 subset: one final status
from 200 to 599, ASCII status and header syntax, exact CRLF, token header names,
one decimal Content-Length, sole Transfer-Encoding: chunked, or an EOF-delimited
body when neither framing field exists. A 204 has zero body. HTTP 401/407 refuse
authentication and 3xx refuse redirects. Informational/upgrade responses,
duplicate Content-Length (even equal), conflicting length/transfer framing,
invalid or overflowing lengths, repeated/unsupported transfer codings, obsolete
header folding, whitespace before a header colon, and any Content-Encoding refuse.
Chunk extensions and trailers are unsupported and refuse; chunk lengths use
checked hexadecimal arithmetic and require complete data, exact CRLF and the zero
chunk's final CRLF. Early EOF refuses declared or chunked bodies. EOF-delimited
success requires an actual EOF. These rules provide no general HTTP engine.

Response headers, including their terminator, are limited to 8192 wire bytes.
Aggregate framing metadata is separately limited to 8192 bytes, including headers,
chunk-size lines, chunk-data CRLF and zero-chunk/terminal framing, excluding body
bytes. Decoded body bytes are limited to 65536; a valid declared length or chunk
that exceeds the remaining allowance refuses `responseTooLarge`. Malformed or
excessive framing refuses `transportFailed`. Only bounded header/framing state
and a 4096-byte receive buffer are retained, with no whole-body retention or
decompression. At most four syscall attempts and 16384 received bytes are handled
per readiness event before yielding to cancellation and the deadline.

A retained offline observation refuses. Editing, choice removal, refresh and new
revisions invalidate pending work. Operation identity fences late callbacks;
a fresh explicit action can use the newly applied revision. Completion runs on
the main actor exactly once, and clears pending authority before invoking callers.

This is a bounded source interface for controlled loopback proof. Verification,
independent correctness/security review and publication are recorded separately. Acceptance
requires an actual selected proxy to receive the absolute-form GET while an
independent live origin receives zero connections, including proxy failure and
an IPv6 absolute target through the IPv4 proxy. The earlier URLSession proxy
candidates did not establish that route. This source grants no general proxy,
PAC/authentication, vendor, artifact, support/report transport, installation,
helper, app launch, production trust, native installed acceptance or client
release authority. Verification and independent acceptance remain separate
from implementation.
