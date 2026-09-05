// Locates the Quickshell source tree for the tests in this directory.
//
// The tests used to live inside that tree, at Common/tests/, which meant the
// Ansible copies them into the vendor runtime along with the shell —
// non-runtime files accumulating in a directory that is supposed to be
// disposable. They are repo tests, so they live with the other repo tests now.
const path = require("node:path");

const shellDir = path.resolve(__dirname, "../../roles/desktop/files/quickshell");

// require() a pure-JS helper out of Common/ by name.
function load(name) {
    return require(path.join(shellDir, "Common", name));
}

module.exports = { shellDir, load };
