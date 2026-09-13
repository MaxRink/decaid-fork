# Sensor path ID decoding

Plugin sensor IDs are opaque strings and can contain URI reserved characters.
Sensor route captures therefore need one decode at each route boundary before
lookup. REST manifest and command routes, plus WebSocket snapshot binding and
replacement rebinding, use the decoded ID so encoded instances remain
independent. Unknown IDs retain the existing REST 404 and WebSocket error
behavior. Paths containing invalid UTF-8 percent-encoded bytes are rejected at
the HTTP boundary.
