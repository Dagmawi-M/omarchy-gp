import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Controls.Basic

Window {
    id: tw
    width: 840; height: 820
    minimumWidth: 840; maximumWidth: 840
    minimumHeight: 820; maximumHeight: 820
    visible: false
    title: "GlobalProtect Traffic"
    transientParent: null
    color: "#0B0C0E"

    readonly property color surface: "#15171B"
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.06)
    readonly property color textMain: "#E6E7EC"
    readonly property color textDim: "#B4B8C2"
    readonly property color accent: "#AAC7FF"
    readonly property bool connected: backend.state === "connected"
    property string filter: "All"
    property string siteResult: ""
    property bool siteVpn: false
    property var rows: []
    property string rowsKey: ""

    // Only replace the list when its contents really changed, and keep the
    // scroll position, so the view does not flicker or jump on each refresh.
    function sync() {
        var f = backend.connections.filter(function(r) {
            return tw.filter === "All" || (tw.filter === "VPN") === r.vpn
        })
        var k = JSON.stringify(f)
        if (k === tw.rowsKey) return
        tw.rowsKey = k
        var y = list.contentY
        tw.rows = f
        Qt.callLater(function() { list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height)) })
    }

    onVisibleChanged: { backend.setTrafficVisible(visible); if (visible) sync() }
    onFilterChanged: { list.contentY = 0; sync() }
    Shortcut { sequence: "Escape"; onActivated: tw.hide() }

    Connections {
        target: backend
        function onSiteChecked(text, vpn) { tw.siteResult = text; tw.siteVpn = vpn }
        function onTrafficChanged() { tw.sync() }
    }

    component Icon: Shape {
        id: ic
        property string d
        property color stroke: "#FFFFFF"
        property real sw: 1.9
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ic.stroke; strokeWidth: ic.sw; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            scale: Qt.size(ic.width / 24, ic.height / 24)
            PathSvg { path: ic.d }
        }
    }

    component Card: Rectangle {
        radius: 24; color: tw.surface
        border.width: 1; border.color: tw.hairline
    }

    component RouteChip: Rectangle {
        property bool vpn
        width: label.width + 24; height: 26; radius: 13
        color: vpn ? "#284777" : "transparent"
        border.width: vpn ? 0 : 1; border.color: "#5B606B"
        Text {
            id: label
            anchors.centerIn: parent; text: parent.vpn ? "VPN" : "Direct"
            color: parent.vpn ? "#E3ECFF" : tw.textMain
            font.pixelSize: 12; font.weight: parent.vpn ? Font.DemiBold : Font.Medium
        }
    }

    Column {
        id: col
        anchors.fill: parent; anchors.margins: 24; anchors.leftMargin: 28; anchors.rightMargin: 28
        spacing: 16

        // Header
        Item {
            width: parent.width; height: 64
            Column {
                spacing: 2
                Text { text: "Traffic"; color: tw.textMain; font.pixelSize: 36; font.weight: Font.DemiBold; font.letterSpacing: -1.1 }
                Text {
                    color: tw.textDim; font.pixelSize: 14
                    text: tw.connected ? "Only the connections marked VPN go through the tunnel. Everything else goes straight to the internet."
                        : "The VPN is off, so nothing is going through it."
                }
            }
            Rectangle {
                anchors.right: parent.right; y: 6
                width: liveRow.width + 28; height: 32; radius: 16
                color: tw.surface; border.width: 1; border.color: tw.hairline
                Row {
                    id: liveRow
                    anchors.centerIn: parent; spacing: 8
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: "#9BE0B4" }
                    Text { text: "Live"; color: "#C9CCD5"; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }
        }

        // Summary
        Row {
            width: parent.width; spacing: 12
            Card {
                width: (parent.width - 12) / 2; height: 118
                color: tw.connected ? "#1F3A63" : tw.surface
                border.width: tw.connected ? 0 : 1
                Column {
                    x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Row {
                        spacing: 8
                        Icon { width: 16; height: 16; stroke: tw.connected ? "#C7D7F5" : tw.textDim; d: "M12 3l7 3v5.5c0 4.3-2.9 8.1-7 9.5-4.1-1.4-7-5.2-7-9.5V6l7-3z" }
                        Text { text: "Through the VPN"; color: tw.connected ? "#C7D7F5" : tw.textDim; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                    Text {
                        text: !backend.trafficReady ? "…" : backend.vpnCount + (backend.vpnCount === 1 ? " connection" : " connections")
                        color: tw.connected ? "#FFFFFF" : tw.textMain
                        font.pixelSize: 30; font.weight: Font.DemiBold; font.letterSpacing: -0.5
                    }
                    Text {
                        text: tw.connected ? backend.down + " down  ·  " + backend.up + " up this session" : "Not connected"
                        color: tw.connected ? "#C7D7F5" : tw.textDim; font.pixelSize: 13
                    }
                }
            }
            Card {
                width: (parent.width - 12) / 2; height: 118
                Column {
                    x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Row {
                        spacing: 8
                        Icon { width: 16; height: 16; stroke: tw.textDim; d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M3 12h18 M12 3c2.8 3 2.8 15 0 18 M12 3c-2.8 3-2.8 15 0 18" }
                        Text { text: "Direct to the internet"; color: tw.textDim; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                    Text {
                        text: !backend.trafficReady ? "…" : backend.directCount + (backend.directCount === 1 ? " connection" : " connections")
                        color: tw.textMain; font.pixelSize: 30; font.weight: Font.DemiBold; font.letterSpacing: -0.5
                    }
                    Text { text: "Does not pass through the VPN gateway"; color: tw.textDim; font.pixelSize: 13 }
                }
            }
        }

        // Check a site
        Card {
            width: parent.width; height: 68
            Text { id: checkLabel; x: 20; anchors.verticalCenter: parent.verticalCenter; text: "Check a site"; color: tw.textMain; font.pixelSize: 14; font.weight: Font.Medium }
            TextField {
                id: site
                anchors.left: checkLabel.right; anchors.leftMargin: 14
                anchors.right: resultChip.visible ? resultChip.left : checkBtn.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 44; leftPadding: 16; rightPadding: 16
                placeholderText: "youtube.com"; placeholderTextColor: "#8A8F9A"
                color: tw.textMain; font.pixelSize: 14
                Accessible.name: "Site to check"
                background: Rectangle { radius: 22; color: "#0B0C0E"; border.width: 1; border.color: site.activeFocus ? tw.accent : "#5B606B" }
                onAccepted: backend.checkSite(text)
                onTextEdited: tw.siteResult = ""
            }
            Rectangle {
                id: resultChip
                visible: tw.siteResult !== ""
                anchors.right: checkBtn.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                width: resultText.width + 28; height: 32; radius: 16
                color: tw.siteVpn ? "#284777" : "transparent"
                border.width: tw.siteVpn ? 0 : 1; border.color: "#5B606B"
                Text { id: resultText; anchors.centerIn: parent; text: tw.siteResult; color: tw.siteVpn ? "#E3ECFF" : tw.textMain; font.pixelSize: 13; font.weight: Font.Medium }
            }
            Rectangle {
                id: checkBtn
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                width: 92; height: 44; radius: 22; color: tw.accent
                activeFocusOnTab: true
                Accessible.role: Accessible.Button; Accessible.name: "Check"
                Keys.onReturnPressed: backend.checkSite(site.text)
                Text { anchors.centerIn: parent; text: "Check"; color: "#0A305F"; font.pixelSize: 14; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: backend.checkSite(site.text) }
            }
        }

        // Live connections
        Card {
            width: parent.width
            height: col.height - 64 - 118 - 68 - (dnsCard.visible ? dnsCard.height + 16 : 0) - 48
            Item {
                id: listHead
                x: 20; y: 12; width: parent.width - 40; height: 40
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Live connections"; color: tw.textMain; font.pixelSize: 15; font.weight: Font.DemiBold }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: seg.width + 8; height: 40; radius: 20; color: "#0B0C0E"
                    Row {
                        id: seg
                        anchors.centerIn: parent; spacing: 4
                        Repeater {
                            model: ["All", "VPN", "Direct"]
                            delegate: Rectangle {
                                required property string modelData
                                width: segText.width + 28; height: 32; radius: 16
                                color: tw.filter === modelData ? "#2A2E36" : "transparent"
                                activeFocusOnTab: true
                                Accessible.role: Accessible.RadioButton; Accessible.name: "Show " + modelData
                                Keys.onReturnPressed: tw.filter = modelData
                                Text { id: segText; anchors.centerIn: parent; text: modelData; color: tw.filter === modelData ? tw.textMain : tw.textDim; font.pixelSize: 13; font.weight: Font.Medium }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tw.filter = modelData }
                            }
                        }
                    }
                }
            }
            Row {
                id: colHead
                x: 20; y: 56; height: 28
                Text { width: 370; text: "Destination"; color: tw.textDim; font.pixelSize: 12 }
                Text { width: 150; text: "App"; color: tw.textDim; font.pixelSize: 12 }
                Text { width: 130; text: "Data"; color: tw.textDim; font.pixelSize: 12 }
                Text { text: "Route"; color: tw.textDim; font.pixelSize: 12 }
            }
            ListView {
                id: list
                x: 20; y: 84; width: parent.width - 40; height: parent.height - 96
                clip: true
                model: tw.rows
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    required property var modelData
                    width: list.width; height: 44
                    Rectangle { width: parent.width; height: 1; color: "#23262C" }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        Item {
                            width: 370; height: 20
                            Text {
                                id: siteName
                                width: Math.min(implicitWidth, 354 - ipText.implicitWidth); elide: Text.ElideRight
                                text: modelData.name || modelData.dest
                                color: tw.textMain; font.pixelSize: 14; font.weight: Font.Medium
                            }
                            Text {
                                id: ipText
                                anchors.left: siteName.right; anchors.leftMargin: 10; anchors.baseline: siteName.baseline
                                text: (modelData.name ? modelData.dest : "") + (modelData.udp ? "  UDP" : "") + (modelData.count > 1 ? "  ×" + modelData.count : "")
                                color: "#8A8F9A"; font.pixelSize: 12
                            }
                        }
                        Text { width: 150; elide: Text.ElideRight; text: modelData.app; color: tw.textDim; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: 130; text: modelData.data || "–"; color: "#C9CCD5"; font.pixelSize: 14 }
                        RouteChip { vpn: modelData.vpn }
                    }
                }
                Text {
                    visible: list.count === 0
                    anchors.centerIn: parent; color: tw.textDim; font.pixelSize: 14
                    text: !backend.trafficReady ? "Reading connections…"
                        : tw.filter === "VPN" ? "Nothing is using the VPN right now." : "No open connections."
                }
            }
        }

        // DNS note
        Card {
            id: dnsCard
            visible: tw.connected
            opacity: backend.dns !== "" ? 1 : 0
            width: parent.width; height: 78
            Icon { x: 20; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sw: 1.8; stroke: "#F2C879"; d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M12 8v5 M12 16.5h.01" }
            Column {
                x: 54; width: parent.width - 74; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Text {
                    text: backend.dnsViaVpn ? "Site name lookups are going through the VPN" : "Site name lookups can go through the VPN"
                    color: tw.textMain; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; color: tw.textDim; font.pixelSize: 13
                    text: (backend.dnsViaVpn ? "This machine is asking your organisation's DNS servers (" : "While connected, name lookups can be sent to your organisation's DNS servers (")
                        + backend.dns + ") for site names. The names are visible there even when the page itself loads directly."
                }
            }
        }
    }
}
