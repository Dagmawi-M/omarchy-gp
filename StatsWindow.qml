import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

Window {
    id: sw
    width: 840; height: 760
    minimumWidth: 840; maximumWidth: 840
    minimumHeight: 760; maximumHeight: 760
    visible: false
    title: "GlobalProtect Dashboard"
    transientParent: null
    color: "#0B0C0E"

    readonly property color surface: "#15171B"
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.06)
    readonly property color textMain: "#E6E7EC"
    readonly property color textDim: "#B4B8C2"
    readonly property color accent: "#AAC7FF"
    readonly property var stats: backend.stats
    property string metric: "Time"

    function reveal() { backend.refreshStats(); show(); raise(); requestActivate() }
    Shortcut { sequence: "Escape"; onActivated: sw.hide() }

    component Card: Rectangle {
        radius: 24; color: sw.surface
        border.width: 1; border.color: sw.hairline
    }

    component Summary: Card {
        property string label
        property var rec
        property bool lead: false
        height: 118
        color: lead ? "#1F3A63" : sw.surface
        border.width: lead ? 0 : 1
        Column {
            x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Text { text: parent.parent.label; color: parent.parent.lead ? "#C7D7F5" : sw.textDim; font.pixelSize: 13; font.weight: Font.Medium }
            Text {
                text: parent.parent.rec ? parent.parent.rec.time : ""
                color: parent.parent.lead ? "#FFFFFF" : sw.textMain
                font.pixelSize: 28; font.weight: Font.DemiBold; font.letterSpacing: -0.5
            }
            Text {
                text: parent.parent.rec ? parent.parent.rec.data + " through the VPN  ·  " + parent.parent.rec.sessions : ""
                color: parent.parent.lead ? "#C7D7F5" : sw.textDim; font.pixelSize: 13
            }
        }
    }

    Column {
        anchors.fill: parent; anchors.margins: 24; anchors.leftMargin: 28; anchors.rightMargin: 28
        spacing: 16

        Column {
            width: parent.width; spacing: 2
            Text { text: "Dashboard"; color: sw.textMain; font.pixelSize: 36; font.weight: Font.DemiBold; font.letterSpacing: -1.1 }
            Text {
                text: "Time connected and data sent through the VPN, recorded while this panel is running."
                color: sw.textDim; font.pixelSize: 14
            }
        }

        Row {
            width: parent.width; spacing: 12
            Summary { width: (parent.width - 24) / 3; label: "Today"; rec: sw.stats.today; lead: true }
            Summary { width: (parent.width - 24) / 3; label: "Last 7 days"; rec: sw.stats.week }
            Summary { width: (parent.width - 24) / 3; label: "Last 30 days"; rec: sw.stats.month }
        }

        // Daily chart
        Card {
            width: parent.width; height: 300
            Text { x: 20; y: 18; text: "Last 14 days"; color: sw.textMain; font.pixelSize: 15; font.weight: Font.DemiBold }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 16; y: 10
                width: seg.width + 8; height: 40; radius: 20; color: "#0B0C0E"
                Row {
                    id: seg
                    anchors.centerIn: parent; spacing: 4
                    Repeater {
                        model: ["Time", "Data"]
                        delegate: Rectangle {
                            required property string modelData
                            width: segText.width + 28; height: 32; radius: 16
                            color: sw.metric === modelData ? "#2A2E36" : "transparent"
                            activeFocusOnTab: true
                            Accessible.role: Accessible.RadioButton; Accessible.name: "Show " + modelData
                            Keys.onReturnPressed: sw.metric = modelData
                            Text { id: segText; anchors.centerIn: parent; text: modelData; color: sw.metric === modelData ? sw.textMain : sw.textDim; font.pixelSize: 13; font.weight: Font.Medium }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.metric = modelData }
                        }
                    }
                }
            }
            Row {
                id: bars
                x: 20; y: 64; width: parent.width - 40; height: 216
                readonly property real slot: width / 14
                Repeater {
                    model: sw.stats.days
                    delegate: Item {
                        required property var modelData
                        readonly property real frac: sw.metric === "Time" ? modelData.timeFrac : modelData.dataFrac
                        readonly property string value: sw.metric === "Time" ? modelData.timeShort : modelData.dataShort
                        width: bars.slot; height: bars.height
                        Accessible.name: modelData.day + " " + modelData.num + ": " + modelData.time + ", " + modelData.data
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: bar.y - 18
                            text: parent.value; visible: parent.frac > 0
                            color: modelData.today ? sw.textMain : sw.textDim; font.pixelSize: 11
                        }
                        Rectangle {
                            id: bar
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(34, parent.width - 14)
                            height: parent.frac > 0 ? Math.max(4, parent.frac * 150) : 2
                            y: 172 - height
                            radius: Math.min(8, height / 2)
                            color: parent.frac > 0 ? (modelData.today ? sw.accent : "#4A5F8A") : "#23262C"
                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 180; spacing: 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.num; color: modelData.today ? sw.textMain : "#C9CCD5"; font.pixelSize: 12; font.weight: modelData.today ? Font.DemiBold : Font.Normal }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.day; color: sw.textDim; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }

        // Per-day figures
        Card {
            width: parent.width; height: 760 - 48 - 62 - 118 - 300 - 48
            Row {
                x: 20; y: 12; height: 28
                Text { width: 200; text: "Day"; color: sw.textDim; font.pixelSize: 12 }
                Text { width: 180; text: "Connected"; color: sw.textDim; font.pixelSize: 12 }
                Text { width: 140; text: "Down"; color: sw.textDim; font.pixelSize: 12 }
                Text { width: 140; text: "Up"; color: sw.textDim; font.pixelSize: 12 }
                Text { text: "Sessions"; color: sw.textDim; font.pixelSize: 12 }
            }
            ListView {
                id: dayList
                x: 20; y: 40; width: parent.width - 40; height: parent.height - 52
                clip: true
                model: sw.stats.recent
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    required property var modelData
                    width: dayList.width; height: 38
                    Rectangle { width: parent.width; height: 1; color: "#23262C" }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { width: 200; text: modelData.label; color: sw.textMain; font.pixelSize: 14; font.weight: modelData.today ? Font.DemiBold : Font.Normal }
                        Text { width: 180; text: modelData.time; color: "#C9CCD5"; font.pixelSize: 14 }
                        Text { width: 140; text: modelData.down; color: "#C9CCD5"; font.pixelSize: 14 }
                        Text { width: 140; text: modelData.up; color: "#C9CCD5"; font.pixelSize: 14 }
                        Text { text: modelData.count; color: "#C9CCD5"; font.pixelSize: 14 }
                    }
                }
                Text {
                    visible: dayList.count === 0
                    anchors.centerIn: parent; color: sw.textDim; font.pixelSize: 14
                    text: "Nothing recorded yet. Figures appear once you have been connected."
                }
            }
        }
    }
}
