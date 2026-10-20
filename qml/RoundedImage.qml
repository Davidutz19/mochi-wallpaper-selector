import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.island

// An image file cropped to fill its size, with rounded corners. Loaded at the
// size it's shown, so a folder of 4K wallpapers stays light.
Item {
    id: root

    property string path: ""
    property real radius: Theme.radiusField
    readonly property bool ready: image.status === Image.Ready

    // Until the image is there, and for a file it can't read.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.raised

        Symbol {
            anchors.centerIn: parent
            visible: !root.ready
            name: image.status === Image.Error ? "broken_image" : "image"
            size: Math.min(28, parent.height / 3)
            color: Theme.muted
        }
    }

    Image {
        id: image

        anchors.fill: parent
        source: root.path ? `file://${encodeURI(root.path)}` : ""
        sourceSize.width: Math.ceil(root.width * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(root.height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.ready
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
