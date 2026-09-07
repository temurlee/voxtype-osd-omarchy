import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string daemonState: "idle"
    property var audio: null
    property var theme: null
    property var recipe: null
    property string assetRoot: ""

    readonly property string stateHome:
        Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    readonly property string currentThemePath: stateHome + "/omarchy/current/theme"
    property var themeColors: ({})
    property var shellColors: ({})

    function parseThemeColors(raw) {
        const parsed = {};
        const lines = String(raw || "").split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
            if (match) parsed[match[1]] = match[2];
        }
        themeColors = parsed;
    }

    function parseShellColors(raw) {
        const parsed = {};
        const lines = String(raw || "").split("\n");
        let section = "";
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            const sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]/);
            if (sectionMatch) {
                section = sectionMatch[1];
                continue;
            }
            const valueMatch = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']?([^"'#]+|#[0-9A-Fa-f]{6})["']?/);
            if (section && valueMatch)
                parsed[section + "." + valueMatch[1]] = valueMatch[2].trim();
        }
        shellColors = parsed;
    }

    function resolveColor(value, fallback) {
        let token = String(value || "").trim().split(/\s+/)[0];
        for (let i = 0; i < 4 && shellColors[token]; ++i)
            token = String(shellColors[token]).trim().split(/\s+/)[0];
        if (themeColors[token]) token = themeColors[token];
        if (!/^#[0-9A-Fa-f]{6}$/.test(token)) token = fallback;
        return token;
    }

    function notificationColor(key, fallbackRole, fallback) {
        return resolveColor(shellColors["notifications." + key] || fallbackRole, fallback);
    }

    function withAlpha(value, alpha) {
        const color = Qt.color(value);
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    readonly property color backgroundColor:
        withAlpha(notificationColor("background", "background", "#1a1b26"),
                  Number(shellColors["notifications.background-alpha"] || 1))
    readonly property color accentColor:
        notificationColor("countdown", "accent", "#7aa2f7")
    readonly property color foregroundColor:
        notificationColor("text", "foreground", "#a9afd5")
    readonly property color borderColor:
        withAlpha(notificationColor("border", "accent", "#7aa2f7"),
                  Number(shellColors["notifications.border-alpha"] || 1))
    readonly property color foregroundDim: Qt.rgba(
        foregroundColor.r,
        foregroundColor.g,
        foregroundColor.b,
        0.3
    )

    readonly property bool listening:
        daemonState === "recording" || daemonState === "streaming"
    property int rhythmFrame: 0
    property real latestPeak: 0
    property real latestRms: 0
    property bool latestVad: false
    property var barLevels: [0.14, 0.20, 0.16, 0.12]
    readonly property var rhythm: [
        [0.20, 0.72, 0.34, 0.82],
        [0.74, 0.24, 0.86, 0.38],
        [0.32, 0.92, 0.48, 0.68],
        [0.88, 0.42, 0.22, 0.76],
        [0.40, 0.78, 0.70, 0.26],
        [0.68, 0.30, 0.94, 0.50],
        [0.24, 0.84, 0.38, 0.90],
        [0.80, 0.46, 0.76, 0.28]
    ]

    FileView {
        path: root.currentThemePath + "/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.parseThemeColors(text())
        onFileChanged: reload()
    }

    FileView {
        path: root.currentThemePath + "/shell.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.parseShellColors(text())
        onFileChanged: reload()
        onLoadFailed: root.parseShellColors("")
    }

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    function updateBars() {
        const voice = clamp(latestRms * 7.0 + latestPeak * 1.35, 0, 1);
        const activity = latestVad ? voice : voice * 0.55;
        const shape = rhythm[rhythmFrame];
        const next = [];
        for (let i = 0; i < 4; ++i) {
            const floor = 0.08 + shape[i] * 0.08;
            next.push(clamp(floor + activity * (0.30 + shape[i] * 0.70), 0.08, 1));
        }
        barLevels = next;
        rhythmFrame = (rhythmFrame + 1) % rhythm.length;
    }

    onListeningChanged: {
        if (!listening) {
            latestPeak = 0;
            latestRms = 0;
            latestVad = false;
            barLevels = [0.14, 0.20, 0.16, 0.12];
        }
    }

    Connections {
        target: root.audio
        enabled: root.audio !== null

        function onFrameReceived(peak, rms, vad, tsMs) {
            root.latestPeak = peak;
            root.latestRms = rms;
            root.latestVad = vad;
        }

        function onDisconnected() {
            root.latestPeak = 0;
            root.latestRms = 0;
            root.latestVad = false;
        }
    }

    Timer {
        running: root.listening
        repeat: true
        interval: 160
        triggeredOnStart: true
        onTriggered: root.updateBars()
    }

    Rectangle {
        x: Math.round((root.width - width) / 2)
        y: root.height - height - 56
        width: 114
        height: 35
        color: root.backgroundColor
        border.width: 1
        border.color: root.borderColor

        Text {
            visible: root.listening
            x: 11
            anchors.verticalCenter: parent.verticalCenter
            text: "Listening"
            color: root.foregroundColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Normal
            font.letterSpacing: -0.12
        }

        Item {
            visible: root.daemonState === "transcribing"
            x: 13
            width: 93
            height: 16
            anchors.verticalCenter: parent.verticalCenter

            Canvas {
                id: processingText
                anchors.fill: parent
                property real shimmer: 0

                NumberAnimation on shimmer {
                    running: root.daemonState === "transcribing"
                    loops: Animation.Infinite
                    from: 0
                    to: 1
                    duration: 1400
                    easing.type: Easing.Linear
                }

                onShimmerChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                Connections {
                    target: root
                    function onForegroundColorChanged() { processingText.requestPaint(); }
                }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const offset = (-1 + shimmer) * width;
                    const gradient = ctx.createLinearGradient(offset, 0, offset + 2 * width, 0);
                    gradient.addColorStop(0.00, root.foregroundDim);
                    gradient.addColorStop(0.25, root.foregroundColor);
                    gradient.addColorStop(0.50, root.foregroundDim);
                    gradient.addColorStop(0.75, root.foregroundColor);
                    gradient.addColorStop(1.00, root.foregroundDim);
                    ctx.fillStyle = gradient;
                    ctx.font = "12px 'JetBrainsMono Nerd Font'";
                    ctx.textBaseline = "top";
                    ctx.fillText("Processing...", 0, 0);
                }
            }
        }

        Item {
            visible: root.listening
            x: 86
            y: 10.558
            width: 15.5
            height: 13.884

            Repeater {
                model: 4

                Rectangle {
                    id: bar
                    required property int index
                    readonly property real minimum: index === 1 ? 5 : index === 2 ? 3.5 : 2
                    readonly property real range: index === 1 ? 8.884 : index === 2 ? 6.2 : 3
                    readonly property real targetHeight: minimum + range * root.barLevels[index]

                    x: index * 4.5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: targetHeight
                    color: root.accentColor

                    Behavior on height {
                        NumberAnimation {
                            duration: bar.targetHeight > bar.height ? 90 : 140
                            easing.type: bar.targetHeight > bar.height
                                ? Easing.OutQuad
                                : Easing.InOutQuad
                        }
                    }
                }
            }
        }
    }
}
