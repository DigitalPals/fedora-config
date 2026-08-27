import QtQuick
import QtTest
import "../../roles/desktop/files/quickshell/Common/Format.js" as Format
import "../../roles/desktop/files/quickshell/Common/LayoutHelpers.js" as Layout
import "../../roles/desktop/files/quickshell/Common/T3CodeHelpers.js" as T3

Item {
    TestCase {
        name: "QmlJavaScriptRuntime"

        function test_format_boundaries() {
            compare(Format.clamp01(-0.1), 0);
            compare(Format.clamp01(1.1), 1);
            compare(Format.mmss(125.9), "2:05");
            compare(Format.mmss(Number.NaN), "0:00");
        }

        function test_layout_move_contract() {
            const result = Layout.moveWidget({
                left: [{ id: "a", on: true }, { id: "b", on: true }],
                center: [{ id: "clock", on: true }],
                right: []
            }, "left", "a", "center", 1);
            verify(result !== null);
            compare(result.col, "center");
            compare(result.idx, 1);
            compare(result.mods.left[0].id, "b");
            compare(result.mods.center[1].id, "a");
        }

        function test_t3_diff_is_bounded() {
            const rendered = T3.truncateDiff("line\n".repeat(3000), 100000, 2000);
            verify(rendered.truncated);
            verify(rendered.text.length <= 100000);
            verify(rendered.text.split("\n").length <= 2000);
        }
    }
}
