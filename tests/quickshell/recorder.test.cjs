const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

test("the recording PID is published last as a verified ready marker", () => {
    const script = fs.readFileSync(path.resolve(__dirname, "../../assets/scripts/screen-record"),
        "utf8");
    const tail = script.slice(script.lastIndexOf("if ! kill -0"));

    const outputAt = tail.indexOf('publish_state "$OUTPUT_FILE_STATE"');
    const stampAt = tail.indexOf('publish_state "$STARTED_AT_STATE"');
    const ticksAt = tail.indexOf('publish_state "$START_TICKS_STATE"');
    const pidAt = tail.indexOf('publish_state "$PID_FILE"');
    assert.ok(outputAt >= 0 && stampAt > outputAt && ticksAt > stampAt
        && pidAt > ticksAt,
        "consumers must not see active before the output path and start time exist");
    assert.match(script, /exec 9>"\$STATE_DIR\/action\.lock"[\s\S]*flock -n 9/,
        "start and stop must share one lock");
    assert.doesNotMatch(script, /pkill slurp/,
        "a recorder action must never kill another program's selector");
    assert.match(script,
        /if kill -0 "\$pid"[\s\S]*recording state was retained[\s\S]*return 2/,
        "a timed-out stop must keep its truthful active marker");
});

test("the recording indicator validates a marker against the live process", () => {
    const recorder = fs.readFileSync(path.join(shellDir, "Common/Recorder.qml"), "utf8");

    assert.match(recorder, /path: root\.recorderPid > 0 \? "\/proc\/" \+ root\.recorderPid \+ "\/comm"/);
    assert.match(recorder,
        /expectedStartTicks === actualStartTicks/,
        "PID identity must include process start time to reject reuse");
    assert.match(recorder, /path: root\.stateDir \+ "\/wf-recorder\.start-ticks"/);
    assert.match(recorder, /root\.recorderName = "";[\s\S]*root\.recomputeActive\(\)/,
        "a process that dies after startup must clear the indicator on the next poll");
});
