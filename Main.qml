import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Controls.Basic

Window {
    id: win
    width: 320; height: 450
    minimumWidth: 320; maximumWidth: 320
    minimumHeight: 450; maximumHeight: 450
    visible: true
    title: "GlobalProtect"
    color: "#0B0C0E"

    readonly property string st: backend.state
    readonly property bool busy: st === "connecting" || st === "disconnecting"
    readonly property bool setup: backend.needsSetup && (st === "disconnected" || st === "error")
    readonly property color surface: "#15171B"
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.06)
    readonly property color textMain: "#E6E7EC"
    readonly property color textDim: "#B4B8C2"
    readonly property color accent: "#AAC7FF"

    readonly property string shield: "M12 3l7 3v5.5c0 4.3-2.9 8.1-7 9.5-4.1-1.4-7-5.2-7-9.5V6l7-3z"

    function reveal() { win.show(); win.raise(); win.requestActivate(); backend.place(); primaryBtn.forceActiveFocus() }
    Component.onCompleted: reveal()
    onClosing: function(close) { close.accepted = false; win.hide() }
    Shortcut { sequence: "Escape"; onActivated: win.hide() }

    Connections {
        target: backend
        function onToggleRequested() { if (win.visible && win.active) win.hide(); else win.reveal() }
        function onCopied() { copiedNote.restart() }
        function onAccountNeeded() { account.reveal() }
        function onWindowRequested(name) {
            if (name === "traffic") { traffic.show(); traffic.raise() }
            else if (name === "dashboard") dashboard.reveal()
            else account.reveal()
        }
    }
    Timer { id: copiedNote; interval: 1400 }

    component Icon: Shape {
        id: ic
        property string d
        property color stroke: "#FFFFFF"
        property real sw: 1.7
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ic.stroke; strokeWidth: ic.sw; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            scale: Qt.size(ic.width / 24, ic.height / 24)
            PathSvg { path: ic.d }
        }
    }

    component Card: Rectangle {
        radius: 20; color: win.surface
        border.width: 1; border.color: win.hairline
    }

    component PillButton: Rectangle {
        id: pb
        property string label
        property color fg: win.textMain
        property int textSize: 16
        property int weight: Font.DemiBold
        signal clicked()
        radius: height / 2
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: pb.clicked()
        Keys.onReturnPressed: pb.clicked()
        Keys.onSpacePressed: pb.clicked()
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: "#FFFFFF"; opacity: ma.pressed ? 0.12 : (ma.containsMouse || pb.activeFocus ? 0.06 : 0)
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Text {
            anchors.centerIn: parent; text: pb.label; color: pb.fg
            font.pixelSize: pb.textSize; font.weight: pb.weight
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14; anchors.leftMargin: 16; anchors.rightMargin: 16
        spacing: 10

        // Top bar
        Item {
            width: parent.width; height: 40
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "GlobalProtect"; color: win.textDim
                font.pixelSize: 14; font.weight: Font.Medium; font.letterSpacing: 0.2
            }
            Rectangle {
                id: settingsBtn
                anchors.right: parent.right; width: 40; height: 40; radius: 20
                color: sma.containsMouse || activeFocus ? "#1F2228" : win.surface
                border.width: 1; border.color: win.hairline
                activeFocusOnTab: true
                Accessible.role: Accessible.Button; Accessible.name: "Settings"
                Keys.onReturnPressed: menu.open()
                Icon {
                    anchors.centerIn: parent; width: 19; height: 19; stroke: "#C9CCD5"
                    d: "M4 7h10 M18 7h2 M14 7a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M4 17h2 M10 17h10 M6 17a2 2 0 1 0 4 0a2 2 0 1 0-4 0"
                }
                MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.open() }

                Popup {
                    id: menu
                    x: parent.width - width; y: parent.height + 8
                    width: 232; padding: 6
                    background: Rectangle { radius: 20; color: "#1B1E23"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08) }
                    contentItem: Column {
                        Repeater {
                            model: [
                                { t: "Traffic", f: function() { traffic.show(); traffic.raise() } },
                                { t: "Dashboard", f: function() { dashboard.reveal() } },
                                { t: "Account", f: function() { account.reveal() } },
                                { t: "Terms and agreement", f: function() { backend.openTerms() } },
                                { t: "Open official client", f: function() { backend.openOfficial() } },
                                { t: "Close panel", f: function() { win.hide() } },
                                { t: "Quit", f: function() { Qt.quit() } }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 220; height: 44; radius: 14
                                color: mma.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                                Accessible.role: Accessible.MenuItem; Accessible.name: modelData.t
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter; x: 14
                                    text: modelData.t; color: win.textMain; font.pixelSize: 14
                                }
                                MouseArea {
                                    id: mma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { menu.close(); modelData.f() }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Status card
        Item {
            id: hero
            width: parent.width; height: 176
            readonly property color fill: win.st === "connected" ? "#1F3A63" : (win.st === "error" ? "#5A1A17" : win.surface)
            readonly property bool tinted: win.st === "connected" || win.st === "error"
            readonly property color onHero: win.st === "connected" ? "#E3ECFF" : (win.st === "error" ? "#FFE2DE" : (win.busy ? win.accent : "#C9CCD5"))
            onFillChanged: bg.requestPaint()

            Canvas {
                id: bg
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d"), r = 28, w = width, h = height
                    c.reset()
                    c.beginPath()
                    c.moveTo(r, 0); c.lineTo(w - r, 0); c.arcTo(w, 0, w, r, r)
                    c.lineTo(w, h - r); c.arcTo(w, h, w - r, h, r)
                    c.lineTo(r, h); c.arcTo(0, h, 0, h - r, r)
                    c.lineTo(0, r); c.arcTo(0, 0, r, 0, r)
                    c.closePath(); c.clip()
                    c.fillStyle = hero.fill; c.fillRect(0, 0, w, h)
                    var cx = w - 18 - 22, cy = 16 + 22
                    var k = hero.tinted ? 1 : 0.6
                    var rings = [[88, 0.022], [62, 0.035], [40, 0.05]]
                    for (var i = 0; i < rings.length; i++) {
                        c.beginPath(); c.arc(cx, cy, rings[i][0], 0, Math.PI * 2)
                        c.fillStyle = Qt.rgba(1, 1, 1, rings[i][1] * k); c.fill()
                    }
                    if (!hero.tinted) {
                        c.beginPath()
                        c.moveTo(r, 0.5); c.lineTo(w - r, 0.5); c.arcTo(w - 0.5, 0.5, w - 0.5, r, r)
                        c.lineTo(w - 0.5, h - r); c.arcTo(w - 0.5, h - 0.5, w - r, h - 0.5, r)
                        c.lineTo(r, h - 0.5); c.arcTo(0.5, h - 0.5, 0.5, h - r, r)
                        c.lineTo(0.5, r); c.arcTo(0.5, 0.5, r, 0.5, r)
                        c.closePath(); c.strokeStyle = Qt.rgba(1, 1, 1, 0.06); c.lineWidth = 1; c.stroke()
                    }
                }
            }

            // Status pill
            Rectangle {
                x: 18; y: 16; height: 28; radius: 14
                width: pillRow.width + 24
                color: hero.tinted ? Qt.rgba(1, 1, 1, 0.12) : "#2A2E36"
                Row {
                    id: pillRow
                    anchors.centerIn: parent; spacing: 8
                    Rectangle {
                        visible: win.st === "connected" || win.st === "disconnected"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: win.st === "connected" ? "#9BE0B4" : "transparent"
                        border.width: win.st === "connected" ? 0 : 1.5; border.color: win.textDim
                    }
                    Text {
                        text: win.st === "connected" ? "Secure" : win.st === "error" ? "Failed"
                            : win.st === "connecting" ? "Signing in" : win.st === "disconnecting" ? "Closing" : "Off"
                        color: hero.onHero; font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
            }

            // Shield
            Rectangle {
                x: parent.width - 18 - 44; y: 16; width: 44; height: 44; radius: 22
                color: hero.tinted ? Qt.rgba(1, 1, 1, 0.12) : "#2A2E36"
                Icon {
                    anchors.centerIn: parent; width: 22; height: 22
                    stroke: win.st === "disconnected" ? win.textDim : hero.onHero
                    d: win.shield + (win.st === "connected" ? " M8.8 12.2l2.3 2.3 4.2-4.6"
                        : win.st === "error" ? " M12 8.5v4.5 M12 16h.01" : "")
                }
            }

            Column {
                x: 18; width: parent.width - 36
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                spacing: 4
                Text {
                    width: parent.width
                    text: win.st === "connected" ? "Connected" : win.st === "error" ? "Couldn't connect"
                        : win.st === "connecting" ? "Connecting" : win.st === "disconnecting" ? "Disconnecting" : "Not connected"
                    color: hero.tinted ? "#FFFFFF" : win.textMain
                    font.pixelSize: win.st === "error" || win.st === "disconnecting" ? 29 : 36
                    font.weight: Font.DemiBold; font.letterSpacing: -1.1
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: win.st === "error" ? backend.error
                        : (backend.gateway || backend.portal) + (win.st === "connected" && backend.uptime ? "  ·  " + backend.uptime : "")
                    color: win.st === "connected" ? "#C7D7F5" : win.st === "error" ? "#FFD3CE" : win.textDim
                    font.pixelSize: 13
                }
                Text {
                    visible: backend.username !== "" && win.st !== "error"
                    width: parent.width; elide: Text.ElideRight
                    text: backend.username
                    color: win.st === "connected" ? "#C7D7F5" : win.textDim
                    font.pixelSize: 13
                }
                Item {
                    visible: win.busy
                    width: parent.width; height: 16
                    Accessible.role: Accessible.ProgressBar; Accessible.name: "In progress"
                    Rectangle {
                        y: 12; width: parent.width; height: 4; radius: 2; color: "#2A2E36"; clip: true
                        Rectangle {
                            width: parent.width * 0.34; height: 4; radius: 2; color: win.accent
                            SequentialAnimation on x {
                                running: win.busy; loops: Animation.Infinite
                                NumberAnimation { from: -120; to: 340; duration: 1500; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }
        }

        // Connected: figures
        Row {
            visible: win.st === "connected"
            width: parent.width; spacing: 8
            Repeater {
                model: [["Down", backend.down], ["Up", backend.up], ["IP", backend.ip]]
                delegate: Card {
                    required property var modelData
                    width: (parent.width - 16) / 3; height: 54
                    Accessible.name: modelData[0] + " " + modelData[1]
                    MouseArea {
                        enabled: modelData[0] === "IP"; anchors.fill: parent
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: backend.copyIp()
                    }
                    Column {
                        x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        Text { text: modelData[0] === "IP" && copiedNote.running ? "Copied" : modelData[0]; color: win.textDim; font.pixelSize: 12 }
                        Text {
                            text: modelData[1]; color: win.textMain
                            font.pixelSize: modelData[0] === "IP" ? 12 : 14; font.weight: Font.Medium
                        }
                    }
                }
            }
        }

        // Connected: traffic entry
        Card {
            visible: win.st === "connected"
            width: parent.width; height: 54
            color: tma.containsMouse || activeFocus ? "#1B1E23" : win.surface
            activeFocusOnTab: true
            Accessible.role: Accessible.Button; Accessible.name: "Traffic. See what goes through the VPN"
            Keys.onReturnPressed: { traffic.show(); traffic.raise() }
            Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sw: 1.8; stroke: win.accent; d: "M3 12h4l3-7 4 14 3-7h4" }
            Column {
                x: 48; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                Text { text: "Traffic"; color: win.textMain; font.pixelSize: 14; font.weight: Font.Medium }
                Text { text: "See what goes through the VPN"; color: win.textDim; font.pixelSize: 12 }
            }
            Icon { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; sw: 1.8; stroke: win.textDim; d: "M9 6l6 6-6 6" }
            MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { traffic.show(); traffic.raise() } }
        }

        // Other states: one line of explanation
        Card {
            visible: win.st !== "connected"
            width: parent.width; height: note.implicitHeight + 28
            Text {
                id: note
                x: 16; y: 14; width: parent.width - 32; wrapMode: Text.WordWrap
                color: win.textDim; font.pixelSize: 13; lineHeight: 1.2
                text: win.setup ? "One step left: approve the setup once, then sign in. After that, Connect is one click and never asks for a password."
                    : win.st === "connecting" ? "Using your saved account. This usually takes about thirty seconds."
                    : win.st === "disconnecting" ? "Closing the tunnel."
                    : win.st === "error" ? "Nothing was changed. Try again, or connect with the official client."
                    : "Internal services are unavailable until you connect."
            }
        }
    }

    // Actions, pinned to the bottom
    Column {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 14; anchors.leftMargin: 16; anchors.rightMargin: 16
        spacing: 8
        PillButton {
            id: primaryBtn
            width: parent.width; height: 50
            enabled: win.st !== "disconnecting"; opacity: enabled ? 1 : 0.5
            label: win.setup ? "Finish setup" : win.st === "connected" ? "Disconnect" : win.st === "connecting" ? "Cancel"
                : win.st === "disconnecting" ? "Disconnecting" : win.st === "error" ? "Try again" : "Connect"
            readonly property bool primary: win.st === "disconnected" || win.st === "error"
            color: primary ? win.accent : (win.st === "connected" ? "#2A2E36" : "transparent")
            border.width: win.busy ? 1 : 0; border.color: "#5B606B"
            fg: primary ? "#0A305F" : win.textMain
            onClicked: win.setup ? backend.setupEngine() : win.st === "connected" ? backend.disconnectVpn()
                : win.st === "connecting" ? backend.cancel() : backend.connectVpn()
        }
        PillButton {
            visible: win.st === "error"
            width: parent.width; height: 40
            label: "Open official client"
            color: win.st === "error" ? "#2A2E36" : "transparent"
            fg: win.st === "error" ? win.textMain : win.accent
            textSize: 13; weight: Font.Medium
            onClicked: backend.openOfficial()
        }
    }

    TrafficWindow { id: traffic }
    AccountWindow { id: account }
    StatsWindow { id: dashboard }
}
