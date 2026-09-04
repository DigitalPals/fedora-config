// Pure model-usage presentation helpers shared by QML and Node tests.
// CLIProxyAPI discovery is represented by the fetcher's source marker: a
// managed provider (including one whose accounts currently fail) carries
// source "cliproxy"; a synthetic no-credentials placeholder does not.

var SUPPORTED_PROVIDER_KEYS = ["claude", "codex", "kimi", "xai"];

function providerKeys(source, data) {
    if (source !== "cliproxy")
        return SUPPORTED_PROVIDER_KEYS.slice();

    var records = data && typeof data === "object" ? data : {};
    return SUPPORTED_PROVIDER_KEYS.filter(function (key) {
        var reading = records[key];
        if (!reading || reading.source !== "cliproxy")
            return false;
        // If a formerly managed credential disappears, resilient polling may
        // briefly return its last reading qualified with the current failure.
        // Treat that authoritative inventory miss as removal, not stale data.
        return reading.staleKind !== "nocreds";
    });
}

function selectedProvider(keys, current) {
    var available = Array.isArray(keys) ? keys : [];
    if (available.indexOf(current) !== -1 || available.length === 0)
        return current;
    return available[0];
}

var exported = {
    SUPPORTED_PROVIDER_KEYS: SUPPORTED_PROVIDER_KEYS,
    providerKeys: providerKeys,
    selectedProvider: selectedProvider
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
