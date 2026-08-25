const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const N = load("LauncherNavigation.js");

test("launcher selection stays valid for empty and single-result lists", () => {
    for (const selected of [-1, 0, 7]) {
        assert.equal(N.clampSelection(selected, 0), 0);
        assert.equal(N.wrapSelection(selected, 0, 1), 0);
        assert.equal(N.pageSelection(selected, 0, 6), 0);
        assert.equal(N.clampSelection(selected, 1), 0);
        assert.equal(N.wrapSelection(selected, 1, -1), 0);
        assert.equal(N.pageSelection(selected, 1, -6), 0);
    }
});

test("launcher result movement wraps at both list boundaries", () => {
    assert.equal(N.wrapSelection(0, 8, -1), 7);
    assert.equal(N.wrapSelection(7, 8, 1), 0);
    assert.equal(N.wrapSelection(3, 8, 1), 4);
});

test("launcher page movement jumps six rows and clamps at the ends", () => {
    assert.equal(N.pageSelection(0, 8, 6), 6);
    assert.equal(N.pageSelection(1, 8, 6), 7);
    assert.equal(N.pageSelection(7, 8, -6), 1);
    assert.equal(N.pageSelection(5, 8, -6), 0);
});
