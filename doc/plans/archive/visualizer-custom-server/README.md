# Custom Visualizer server

Issue #975 adds support for using a self-hosted Visualizer instance from the bundled plugin. The plugin keeps the hosted service as the default, derives every Visualizer endpoint from one validated base URL, and persists mappings and sync cursors per normalized server. A server change waits for persisted state to load before making a request; credentials are cleared for a previously unseen server so a saved password cannot be sent to the wrong host.

The setting accepts only `http` and `https` URLs without query, fragment, username, or password. A path prefix is retained and trailing slashes are removed, allowing reverse proxies such as `https://coffee.example/visualizer`. The plugin reports the active server in status and returns actionable connection errors without including credentials.
