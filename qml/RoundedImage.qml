import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.island

// An image file cropped to fill its size, with rounded corners.
//
// The file is decoded once at `loadSize`, not at the size shown: the picker's
// thumbnails grow and shrink, and decoding at every size in between would
// reload the file each frame. Qt keeps the decoded image in its cache, and a
// reload keeps showing the old one until the new one is there.
Item {
    id: root

    property string path: ""
    property real radius: Theme.radiusField
    // The largest size it's shown at; a folder of 4K wallpapers stays light.
    property size loadSize: Qt.size(width, height)
    // Once it's been shown, it stays shown, through reloads too.
    readonly property bool ready: image.status === Image.Ready || shown
    property bool shown: false

    onPathChanged: shown = false

    // Until the image is there, and for a file it can't read.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.raised
        visible: !root.ready || image.status === Image.Error

        Symbol {
            anchors.centerIn: parent
            name: image.status === Image.Error ? "broken_image" : "image"
            size: Math.min(28, parent.height / 3)
            color: Theme.muted
        }
    }

    Image {
        id: image

        anchors.fill: parent
        source: root.path ? `file://${encodeURI(root.path)}` : ""
        sourceSize.width: Math.ceil(root.loadSize.width * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(root.loadSize.height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        retainWhileLoading: true
        visible: root.ready && status !== Image.Error
        onStatusChanged: {
            if (status === Image.Ready)
                root.shown = true;
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
}
