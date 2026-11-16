import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

Window {
    id: aw
    width: 400; height: 690
    minimumWidth: 400; maximumWidth: 400
    minimumHeight: 690; maximumHeight: 690
    visible: false
    title: "GlobalProtect Account"
    transientParent: null
    color: "#0B0C0E"

    readonly property color surface: "#15171B"
    readonly property color textMain: "#E6E7EC"
    readonly property color textDim: "#B4B8C2"
    readonly property color accent: "#AAC7FF"
    property string problem: ""

    function reveal() {
        portal.text = backend.portal
        user.text = backend.username
        pass.text = ""
        problem = ""
        show(); raise(); requestActivate()
        if (portal.text === "") portal.forceActiveFocus()
        else if (user.text === "") user.forceActiveFocus()
        else pass.forceActiveFocus()
    }

    function submit() {
        problem = backend.signIn(portal.text, user.text, pass.text)
        if (problem === "") { pass.text = ""; hide() }
    }

    onVisibleChanged: if (!visible) pass.text = ""
    Shortcut { sequence: "Escape"; onActivated: aw.hide() }

    component Field: Column {
        property alias text: input.text
        property alias input: input
        property string label
        property string hint
        property bool secret: false
        width: parent.width; spacing: 6
        Text { text: parent.label; color: aw.textMain; font.pixelSize: 13; font.weight: Font.Medium }
        TextField {
            id: input
            width: parent.width; height: 48; leftPadding: 16; rightPadding: 16
            placeholderText: parent.hint; placeholderTextColor: "#8A8F9A"
            color: aw.textMain; font.pixelSize: 14
            echoMode: parent.secret ? TextInput.Password : TextInput.Normal
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Accessible.name: parent.label
            background: Rectangle {
                radius: 16; color: aw.surface
                border.width: 1; border.color: input.activeFocus ? aw.accent : "#5B606B"
            }
            onAccepted: aw.submit()
        }
    }

    Column {
        anchors.fill: parent; anchors.margins: 24
        spacing: 16

        Column {
            width: parent.width; spacing: 4
            Text { text: "Account"; color: aw.textMain; font.pixelSize: 30; font.weight: Font.DemiBold; font.letterSpacing: -0.8 }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "Add or change the VPN account this panel connects with."
                color: aw.textDim; font.pixelSize: 14
            }
        }

        Field { id: portal; label: "Portal"; hint: "vpn.example.com" }
        Field { id: user; label: "Username"; hint: "name.surname" }
        Field { id: pass; label: "Password"; hint: "Your VPN password"; secret: true }

        Text {
            visible: aw.problem !== ""
            width: parent.width; wrapMode: Text.WordWrap
            text: aw.problem; color: "#FFB4AB"; font.pixelSize: 13
        }

        Rectangle {
            id: go
            width: parent.width; height: 52; radius: 26; color: aw.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Button; Accessible.name: "Save and connect"
            Keys.onReturnPressed: aw.submit()
            Keys.onSpacePressed: aw.submit()
            Rectangle { anchors.fill: parent; radius: 26; color: "#FFFFFF"; opacity: gma.pressed ? 0.2 : (gma.containsMouse || go.activeFocus ? 0.1 : 0) }
            Text {
                anchors.centerIn: parent
                text: backend.state === "connected" ? "Save and reconnect" : "Save and connect"
                color: "#0A305F"; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: aw.submit() }
        }

        Rectangle {
            width: parent.width; height: guide.implicitHeight + 32; radius: 20
            color: aw.surface; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.06)
            Column {
                id: guide
                x: 16; y: 16; width: parent.width - 32; spacing: 8
                Text { text: "How this works"; color: aw.textMain; font.pixelSize: 13; font.weight: Font.DemiBold }
                Repeater {
                    model: [
                        "The portal is the address your IT team gave you for GlobalProtect.",
                        "Your password is kept in your system keyring, encrypted, so you only type it once.",
                        "After a successful sign-in, Connect works with one click.",
                        "If your organisation uses a web login or a one-time code, use Open official client instead."
                    ]
                    delegate: Row {
                        required property string modelData
                        required property int index
                        width: guide.width; spacing: 8
                        Text { width: 14; text: (index + 1) + "."; color: aw.accent; font.pixelSize: 13; font.weight: Font.Medium }
                        Text { width: parent.width - 22; wrapMode: Text.WordWrap; text: modelData; color: aw.textDim; font.pixelSize: 13; lineHeight: 1.15 }
                    }
                }
            }
        }
    }
}
