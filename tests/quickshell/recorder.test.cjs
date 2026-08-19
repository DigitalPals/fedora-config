const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

test("the recording PID is published last as a verified ready marker", () => {
    const script = fs.readFileSync(path.resolve(__dirname, "../../assets/scripts/screen-record"),
        "utf8");
    const tail = script.slice(script.lastIndexOf("if ! kill -0"));

    const outputAt = tail.indexOf('> "$OUTPUT_FILE_STATE"');
    const stampAt = tail.indexOf('> "$STARTED_AT_STATE"');
    const pidAt = tail.indexOf('> "$PID_FILE"');
    assert.ok(outputAt >= 0 && stampAt > outputAt && pidAt > stampAt,
        "consumers must not see active before the output path and start time exist");
});

test("the recording chip validates a marker against the live process", () => {
    const recorder = fs.readFileSync(path.join(shellDir, "Common/Recorder.qml"), "utf8");

    assert.match(recorder, /path: root\.recorderPid > 0 \? "\/proc\/" \+ root\.recorderPid \+ "\/comm"/);
    assert.match(recorder, /root\.active = text\(\)\.trim\(\) === "wf-recorder"/);
    assert.match(recorder, /onLoadFailed: root\.active = false/,
        "a process that dies after startup must clear the chip on the next poll");
});
