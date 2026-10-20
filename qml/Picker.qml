import QtQuick
import qs.island

// The wallpaper picker: a strip of the wallpapers with the selected one big in
// the middle. Left and Right (or H and L) move, Home and End jump, Enter sets
// the selected wallpaper and closes, R sets a random one, Escape closes. A
// click selects a wallpaper, a click on the selected one sets it, the wheel
// moves along.
Item {
    id: root

    property var payload: ({})

    readonly property var state: Daemon.state("wallpaper-selector")
    readonly property var wallpapers: state?.wallpapers ?? []
    readonly property string current: state?.current ?? ""
    readonly property string error: state?.error ?? ""
    readonly property var selected: wallpapers[strip.currentIndex] ?? null

    // 16:9, the selected one twice the size of the others.
    readonly property int bigWidth: 320
    readonly property int bigHeight: 180
    readonly property int smallWidth: 160
    readonly property int stripWidth: 720

    implicitWidth: stripWidth + Theme.padding * 2
    implicitHeight: column.implicitHeight + Theme.spaceSmall * 2

    focus: true

    // On the wallpaper that's set, or the first.
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

    function apply(): void {
        if (!selected)
            return;
        Daemon.command("wallpaper-selector", "set", [selected.path]);
        Daemon.event("dismiss");
    }

    onWallpapersChanged: {
        if (strip.currentIndex >= wallpapers.length)
            selectCurrent();
    }

    // Follows a wallpaper set from elsewhere, like R.
    onCurrentChanged: selectCurrent()

    // The view is preloaded and kept, so each opening starts again on the
    // wallpaper that's set, with the keyboard.
    onVisibleChanged: {
        if (!visible)
            return;
        selectCurrent();
        Qt.callLater(() => root.forceActiveFocus());
    }

    Component.onCompleted: {
        selectCurrent();
        Qt.callLater(() => root.forceActiveFocus());
    }

    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)
    Keys.onEscapePressed: Daemon.event("dismiss")
    Keys.onReturnPressed: apply()
    Keys.onEnterPressed: apply()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_H)
            move(-1);
        else if (event.key === Qt.Key_L)
            move(1);
        else if (event.key === Qt.Key_Home)
            move(-wallpapers.length);
        else if (event.key === Qt.Key_End)
            move(wallpapers.length);
        else if (event.key === Qt.Key_R)
            Daemon.command("wallpaper-selector", "random", []);
        else
            return;
        event.accepted = true;
    }

    Column {
        id: column

        x: Theme.padding
        y: Theme.spaceSmall
        width: root.stripWidth
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
                onClicked: Daemon.command("wallpaper-selector", "random", [])
            }
        }

        Item {
            width: root.stripWidth
            height: root.bigHeight + 8

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

            // The selected wallpaper stays in the middle; the strip slides.
            ListView {
                id: strip

                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: Theme.spaceMedium
                clip: true
                model: root.wallpapers
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - root.bigWidth) / 2
                preferredHighlightEnd: (width + root.bigWidth) / 2
                highlightMoveDuration: Theme.reducedMotion ? 0 : 220
                boundsBehavior: Flickable.StopAtBounds
                interactive: false
                // Keeps the thumbnails past the edges alive, so coming back to one
                // doesn't load it again.
                cacheBuffer: root.stripWidth * 4

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

                    width: selected ? root.bigWidth : root.smallWidth
                    height: strip.height

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.reducedMotion ? 0 : 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    RoundedImage {
                        id: image

                        anchors.centerIn: parent
                        width: thumb.width
                        height: thumb.width * 9 / 16
                        path: thumb.modelData.path
                        // Decoded once at the big size, so growing and shrinking never reload it.
                        loadSize: Qt.size(root.bigWidth, root.bigHeight)
                        radius: thumb.selected ? Theme.radiusSurface : Theme.radiusControl
                        opacity: thumb.selected ? 1 : area.containsMouse ? 0.85 : 0.55

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.fast
                            }
                        }
                    }

                    // The selection.
                    Rectangle {
                        anchors.centerIn: image
                        width: image.width + 6
                        height: image.height + 6
                        radius: image.radius + 3
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        visible: thumb.selected
                    }

                    // The one that's set now: a badge when selected, a dot otherwise.
                    Rectangle {
                        anchors.top: image.top
                        anchors.left: image.left
                        anchors.margins: Theme.spaceSmall
                        visible: thumb.isCurrent && thumb.selected
                        width: badge.implicitWidth + Theme.spaceMedium * 2
                        height: 22
                        radius: height / 2
                        color: Theme.accent

                        Row {
                            id: badge

                            anchors.centerIn: parent
                            spacing: Theme.spaceTiny

                            Symbol {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "check"
                                size: 13
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

                    Rectangle {
                        anchors.right: image.right
                        anchors.bottom: image.bottom
                        anchors.margins: Theme.spaceSmall
                        visible: thumb.isCurrent && !thumb.selected
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.accent
                        border.width: 1
                        border.color: Theme.onAccent
                    }

                    MouseArea {
                        id: area

                        anchors.fill: image
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (thumb.selected)
                                root.apply();
                            else
                                strip.currentIndex = thumb.index;
                        }
                    }
                }

                // The wheel moves one wallpaper per step.
                WheelHandler {
                    property real gathered: 0

                    onWheel: event => {
                        gathered += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        while (Math.abs(gathered) >= 120) {
                            root.move(gathered > 0 ? -1 : 1);
                            gathered -= gathered > 0 ? 120 : -120;
                        }
                    }
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
                text: "←→ browse · Enter set · R random · Esc close"
                color: Theme.muted
                font.pixelSize: Theme.textCaption
                font.family: Theme.fontFamily
            }
        }
    }
}
