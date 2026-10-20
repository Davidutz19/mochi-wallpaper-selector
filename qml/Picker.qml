import QtQuick
import qs.island

// The wallpaper picker: a big preview of the selected wallpaper and a strip of
// all of them. Left and Right (or H and L) move, Home and End jump, Enter sets
// the wallpaper and closes, Space sets it and stays open to try another, R sets
// a random one, Escape closes. A click selects a thumbnail, a double click sets
// it, the wheel scrolls the strip.
Item {
    id: root

    property var payload: ({})

    readonly property var state: Daemon.state("wallpaper")
    readonly property var wallpapers: state?.wallpapers ?? []
    readonly property string current: state?.current ?? ""
    readonly property string error: state?.error ?? ""
    readonly property var selected: wallpapers[strip.currentIndex] ?? null

    readonly property int previewWidth: 640
    readonly property int previewHeight: 360
    readonly property int thumbWidth: 112
    readonly property int thumbHeight: 63

    implicitWidth: previewWidth + Theme.padding * 2
    implicitHeight: column.implicitHeight + Theme.spaceSmall * 2

    focus: true

    // Starts on the wallpaper that's set, and stays in range when the folder
    // changes.
    function selectCurrent(): void {
        const at = wallpapers.findIndex(wallpaper => wallpaper.path === current);
        strip.currentIndex = at >= 0 ? at : 0;
        strip.positionViewAtIndex(strip.currentIndex, ListView.Center);
    }

    function move(by: int): void {
        if (wallpapers.length === 0)
            return;
        strip.currentIndex = Math.max(0, Math.min(wallpapers.length - 1, strip.currentIndex + by));
    }

    function apply(close: bool): void {
        if (!selected)
            return;
        Daemon.command("wallpaper", "set", [selected.path]);
        if (close)
            Daemon.event("dismiss");
        else
            light.flash();
    }

    onWallpapersChanged: {
        if (strip.currentIndex >= wallpapers.length)
            selectCurrent();
    }

    Component.onCompleted: {
        selectCurrent();
        Qt.callLater(() => root.forceActiveFocus());
    }

    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)
    Keys.onEscapePressed: Daemon.event("dismiss")
    Keys.onReturnPressed: apply(true)
    Keys.onEnterPressed: apply(true)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_H)
            move(-1);
        else if (event.key === Qt.Key_L)
            move(1);
        else if (event.key === Qt.Key_Home)
            move(-wallpapers.length);
        else if (event.key === Qt.Key_End)
            move(wallpapers.length);
        else if (event.key === Qt.Key_Space)
            apply(false);
        else if (event.key === Qt.Key_R)
            Daemon.command("wallpaper", "random", []);
        else
            return;
        event.accepted = true;
    }

    EdgeLight {
        id: light

        radius: Theme.radiusSurface
    }

    Column {
        id: column

        x: Theme.padding
        y: Theme.spaceSmall
        width: root.previewWidth
        spacing: Theme.spaceMedium

        PanelHeader {
            width: parent.width
            title: "Wallpapers"
            icon: "wallpaper"

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.wallpapers.length > 0
                text: `${strip.currentIndex + 1} / ${root.wallpapers.length}`
                color: Theme.muted
                font.pixelSize: Theme.textCaption
                font.family: Theme.fontFamily
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "shuffle"
                onClicked: Daemon.command("wallpaper", "random", [])
            }
        }

        // The selected wallpaper, big.
        Item {
            width: root.previewWidth
            height: root.previewHeight

            RoundedImage {
                anchors.fill: parent
                visible: root.selected !== null
                path: root.selected?.path ?? ""
                radius: Theme.radiusSurface
            }

            Column {
                anchors.centerIn: parent
                visible: root.wallpapers.length === 0
                spacing: Theme.spaceSmall

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "hide_image"
                    size: 32
                    color: Theme.muted
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `No images in ${root.state?.directory ?? "the folder"}`
                    color: Theme.muted
                    font.pixelSize: Theme.textBody
                    font.family: Theme.fontFamily
                }
            }

            // The one that's set now.
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.spaceMedium
                visible: root.selected !== null && root.selected.path === root.current
                width: badge.implicitWidth + Theme.spaceMedium * 2
                height: 24
                radius: height / 2
                color: Theme.accent

                Row {
                    id: badge

                    anchors.centerIn: parent
                    spacing: Theme.spaceTiny

                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        size: 14
                        color: Theme.onAccent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Current"
                        color: Theme.onAccent
                        font.pixelSize: Theme.textCaption
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightLabel
                    }
                }
            }

            // Arrows on the sides, for the mouse.
            IconButton {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceSmall
                anchors.verticalCenter: parent.verticalCenter
                visible: root.wallpapers.length > 1 && strip.currentIndex > 0
                icon: "chevron_left"
                size: 24
                onClicked: root.move(-1)
            }

            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceSmall
                anchors.verticalCenter: parent.verticalCenter
                visible: root.wallpapers.length > 1 && strip.currentIndex < root.wallpapers.length - 1
                icon: "chevron_right"
                size: 24
                onClicked: root.move(1)
            }
        }

        // Every wallpaper, small.
        ListView {
            id: strip

            width: root.previewWidth
            height: root.thumbHeight + 8
            orientation: ListView.Horizontal
            spacing: Theme.spaceSmall
            clip: true
            model: root.wallpapers
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            ScrollFade {
                view: strip
                horizontal: true
            }

            delegate: Item {
                id: thumb

                required property var modelData
                required property int index
                readonly property bool selected: ListView.isCurrentItem
                readonly property bool isCurrent: modelData.path === root.current

                width: root.thumbWidth
                height: root.thumbHeight + 8

                RoundedImage {
                    x: 0
                    y: 4
                    width: root.thumbWidth
                    height: root.thumbHeight
                    path: thumb.modelData.path
                    radius: Theme.radiusControl
                    opacity: thumb.selected || area.containsMouse ? 1 : 0.6

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.fast
                        }
                    }
                }

                // The selection.
                Rectangle {
                    x: -2
                    y: 2
                    width: root.thumbWidth + 4
                    height: root.thumbHeight + 4
                    radius: Theme.radiusControl + 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.accent
                    visible: thumb.selected
                }

                // A dot on the one that's set now.
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spaceSmall + 4
                    visible: thumb.isCurrent
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent
                    border.width: 1
                    border.color: Theme.onAccent
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.currentIndex = thumb.index
                    onDoubleClicked: {
                        strip.currentIndex = thumb.index;
                        root.apply(true);
                    }
                }
            }

            // The wheel scrolls sideways.
            WheelHandler {
                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                    strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX - delta));
                }
            }
        }

        // The selected one's name, or what went wrong, and the keys.
        Item {
            width: parent.width
            height: 24

            Text {
                anchors.left: parent.left
                anchors.right: hint.left
                anchors.rightMargin: Theme.spaceMedium
                anchors.verticalCenter: parent.verticalCenter
                text: root.error !== "" ? root.error : (root.selected?.name ?? "")
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: root.error !== "" ? Theme.danger : Theme.foreground
                font.pixelSize: Theme.textCaption
                font.family: Theme.fontFamily
            }

            Text {
                id: hint

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "←→ browse · Enter set · Space try · R random"
                color: Theme.muted
                font.pixelSize: Theme.textCaption
                font.family: Theme.fontFamily
            }
        }
    }
}
