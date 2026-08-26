const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const assetsDir = path.join(shellDir, "assets");
const brands = [
    "claude", "github", "kimi", "openai",
    "t3", "tailscale", "whatsapp", "youtube"
];

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

function codeFiles(dir = shellDir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
        const file = path.join(dir, entry.name);
        if (entry.isDirectory())
            return ["assets", "scripts"].includes(entry.name) ? [] : codeFiles(file);
        return /\.(?:qml|js)$/.test(entry.name) ? [file] : [];
    });
}

test("the brand registry and asset directory contain one canonical SVG per product", () => {
    const registry = read("Common/BrandIcons.qml");
    const assets = fs.readdirSync(assetsDir)
        .filter(name => name.endsWith(".svg"))
        .sort();

    assert.deepEqual(assets, brands.map(name => `${name}.svg`).sort());
    for (const name of brands) {
        assert.match(registry, new RegExp(`\\b${name}: "${name}\\.svg"`),
            `${name} must resolve through BrandIcons`);
    }
    assert.doesNotMatch(assets.join("\n"), /-(?:dim|white|dark|light-dim)\.svg$/,
        "contextual tones belong to BrandIcon, not duplicate assets");
});

test("product marks render through BrandIcon rather than ad-hoc asset paths", () => {
    const registry = path.join(shellDir, "Common/BrandIcons.qml");
    for (const file of codeFiles()) {
        if (file === registry)
            continue;
        const source = fs.readFileSync(file, "utf8");
        assert.doesNotMatch(source, /\/assets\/|\.svg["']/,
            `${path.relative(shellDir, file)} bypasses BrandIcons`);
    }

    const icon = read("Common/BrandIcon.qml");
    assert.match(icon, /source:\s*BrandIcons\.source\(root\.name\)/);
    assert.match(icon, /property bool colorized:\s*false/);
    assert.match(icon, /colorizationColor:\s*root\.tint/);
    assert.match(icon, /Accessible\.ignored:\s*true/);

    const notifs = read("Common/Notifs.qml");
    assert.equal((notifs.match(/BrandIcons\.has\(/g) || []).length, 2,
        "notification-supplied and derived brands must both cross the allow-list");
});

test("Quickshell no longer carries a parallel Nerd Font icon path", () => {
    const sources = codeFiles().map(file => fs.readFileSync(file, "utf8")).join("\n");
    assert.doesNotMatch(sources, /fontNerd|JetBrainsMono Nerd Font|/);
});

test("every bundled product mark records pinned provenance and licensing", () => {
    const provenance = read("assets/README.md");
    const licenses = read("assets/THIRD_PARTY_LICENSES.md");

    for (const name of brands)
        assert.match(provenance, new RegExp(`\\b${name}\\.svg\\b`));
    for (const revision of [
        "4a79bb55697c85b8bc9f3caa22be747e0277ad4f",
        "5a0fe38e97784d94279ce4eb1bf85f9a91bf027e",
        "a3a8cbd60539b4af4de8f96c892dbd07a2b6c041"
    ])
        assert.match(provenance, new RegExp(revision));
    assert.match(licenses, /CC0 1\.0 Universal/);
    assert.equal((licenses.match(/MIT License/g) || []).length, 2);
});
