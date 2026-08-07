const test = require("node:test");
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { fileURLToPath } = require("node:url");

const shellDir = path.resolve(__dirname, "../..");
const helper = path.join(shellDir, "scripts/wallpaper-thumbnail.py");

test("wallpaper thumbnails persist, hit the cache, and revise changed sources", t => {
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "qs-thumb-test-"));
    t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));

    const bin = path.join(temporary, "bin");
    const source = path.join(temporary, "wall paper.png");
    const count = path.join(temporary, "magick-count");
    fs.mkdirSync(bin);
    fs.writeFileSync(source, "first image");
    fs.writeFileSync(path.join(bin, "magick"), `#!/bin/sh
printf 'run\\n' >> "$MAGICK_COUNT"
source=$1
for output do :; done
cp "$source" "$output"
`);
    fs.chmodSync(path.join(bin, "magick"), 0o755);

    const env = {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        XDG_CACHE_HOME: path.join(temporary, "cache"),
        MAGICK_COUNT: count,
    };
    const run = () => {
        const result = childProcess.spawnSync("python3", [helper, source], {
            encoding: "utf8",
            env,
        });
        assert.equal(result.status, 0, result.stderr);
        return result.stdout.trim();
    };

    const first = run();
    const second = run();
    assert.equal(second, first);
    assert.equal(fs.readFileSync(count, "utf8").trim().split("\n").length, 1,
        "an unchanged source must not invoke ImageMagick again");
    assert.ok(fs.existsSync(fileURLToPath(new URL(first))));

    fs.writeFileSync(source, "changed image with a different size");
    const changed = run();
    assert.notEqual(changed, first, "the URL revision must invalidate Qt's image cache");
    assert.equal(fs.readFileSync(count, "utf8").trim().split("\n").length, 2);
});

test("the wallpaper grid requests cached previews instead of full images", () => {
    const page = fs.readFileSync(path.join(shellDir, "Settings/WallpaperPage.qml"), "utf8");
    const wallpaper = fs.readFileSync(path.join(shellDir, "Common/Wallpaper.qml"), "utf8");

    assert.match(page, /Wallpaper\.requestThumbnail\(imagePath\)/);
    assert.match(page, /source:\s*cell\.thumbnailSource/);
    assert.match(wallpaper, /wallpaper-thumbnail\.py/);
    assert.match(wallpaper, /property var thumbnailPaths/);
});
