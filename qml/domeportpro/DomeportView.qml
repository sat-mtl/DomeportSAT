import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D
import QtQuick3D.Helpers

import Score.UI as UI
import ca.qc.sat.qmlcomponents
import domeportpro

import "DomeportController.js" as Controller

// View — the DomeportPro user interface (3D scene + a right-hand SidePanel of
// controls, laid out after the gallery SidePanel example).
//
// Presentation only: user interactions set state on `domeportModel` or invoke a
// `Controller.*` action, and the model's change signals are routed back to the
// controller through the Connections blocks below. DomeportController.js is
// imported as a non-library resource, so its functions run in this component's
// scope and reach the element ids (dome, camera, inputSelector, …), the
// injected `domeportModel` and the Score/Util context objects directly.
Item {
    id: view

    // The application state and the host window, injected by DomeportPro.qml.
    property var domeportModel
    property var appWindow

    Component.onCompleted: Controller.initialize()

    // ---- Route model changes to the controller ----
    Connections {
        target: domeportModel

        function onCurrentModeChanged() { Controller.applyMode() }
        function onSourceNameChanged() { Controller.applySourceName() }
        function onNdiSourceNameChanged() { Controller.applyNdiSourceName() }
        function onSpoutSourceNameChanged() { Controller.applySpoutSourceName() }
        function onSyphonSourceNameChanged() { Controller.applySyphonSourceName() }
        function onZoomChanged() { Controller.applyZoom() }
        function onImageFilePathChanged() { Controller.applyImageFilePath() }
        function onVideoFilePathChanged() { Controller.applyVideoFilePath() }
        function onCurrentFormatChanged() { Controller.applyFormat() }
        function onCurrentModelChanged() { Controller.applyModel() }
    }

    Connections {
        target: domeportModel.video

        function onVideoDurationMsecChanged() { Controller.applyVideoDuration() }
        function onPlayheadRequestMsecChanged() { Controller.applyPlayheadRequest() }
    }

    // ---- 3D scene ----
    View3D {
        id: view3d
        anchors.fill: parent
        environment: sceneEnvironment

        SceneEnvironment {
            id: sceneEnvironment
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            backgroundMode: SceneEnvironment.Color
            clearColor: "#555"
        }

        PerspectiveCamera {
            id: camera
            property real cameraHeight: 150
            position: Qt.vector3d(0, cameraHeight, 400)
            eulerRotation: Qt.vector3d(30, 0, 0)
            clipNear: 1
            clipFar: 10000
            fieldOfView: domeportModel.cameraFov

            onPositionChanged: {
                if (!domeportModel.cameraFly) {
                    // keep camera height fixed
                    position.y = cameraHeight
                }
            }

            onEulerRotationChanged: {
                // restrict up/down camera motion from -90 to 90 degrees
                if (eulerRotation.x > 90) {
                    eulerRotation.x = 90
                }
                if (eulerRotation.x < -90) {
                    eulerRotation.x = -90
                }
            }
        }

        Model {
            id: groundPlane
            source: "#Rectangle"
            scale: Qt.vector3d(500, 500, 1)
            eulerRotation: Qt.vector3d(-90, 0, 0)
            position: Qt.vector3d(0, 0, 0)

            materials: [
                CustomMaterial {
                    property TextureInput tex: TextureInput {
                        enabled: true
                        texture: Texture {
                            source: "resources/images/GridBlack.jpg"
                            generateMipmaps: true 
                            mipFilter: Texture.Linear
                        }
                    }
                    shadingMode: CustomMaterial.Unshaded
                    vertexShader: "resources/shaders/groundshader.vert"
                    fragmentShader: "resources/shaders/groundshader.frag"
                }

            ]
        }

        Model {
            id: dome
            source: "resources/models/sato210.mesh"
            position: Qt.vector3d(0, 0, 0)
            scale: Qt.vector3d(100., 100., 100.)

            materials: [
                CustomMaterial {
                    property TextureInput tex: TextureInput {
                        enabled: true
                        texture: Texture {
                            sourceItem: textureDome
                        }
                    }
                    shadingMode: CustomMaterial.Unshaded
                    vertexShader: "resources/shaders/domeshader.vert"
                    fragmentShader: "resources/shaders/domeshader.frag"
                }
            ]
        }
    }

    WasdController {
        id: wasdControl
        controlledObject: camera
        speed: 1.0
        shiftSpeed: 5.0
        mouseEnabled: true
    }

    GamepadController {
        id: gamepadControl
        controlledObject: camera
        speed: 1.0
        shiftSpeed: 2.0
        lookSpeed: 0.8
    }

    UI.TextureSource {
        id: textureDome
        width: 4096
        height: 4096
        fixedColorBufferWidth: 4096
        fixedColorBufferHeight: 4096
        process: "rotate_zoom"
        port: 0
        visible: false
    }

    // ---- File drag-and-drop onto the scene ----
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => Controller.handleFileDrop(drop)
    }

    // ---- Render statistics overlay, pinned to the window's top-right ----
    DebugView {
        id: debugView
        source: view3d
        visible: debugSwitch.checked
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.padding
    }

    // ---- Controls, in a slide-over panel on the left ----
    SidePanel {
        anchors.fill: parent
        panelWidth: 420
        edge: Qt.LeftEdge
        open: false

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            TabBar {
                id: panelTabs
                Layout.fillWidth: true

                CustomTabButton { text: "Source" }
                CustomTabButton { text: "Options" }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: panelTabs.currentIndex

                // ---- Source tab ----
                ScrollView {
                    id: sourceScroll
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: sourceScroll.availableWidth - 2 * Theme.padding
                        x: Theme.padding
                        spacing: Theme.spacing

                        CustomLabel {
                            text: "Source"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeTitle
                            Layout.topMargin: Theme.padding
                        }

                        // Test pattern is a dome-only source (not a video-input
                        // backend). ON selects it; OFF re-applies the input
                        // selector's current backend. `checked` reflects the
                        // live mode, so picking a source also unchecks it.
                        CustomSwitch {
                            text: "Test pattern"
                            checked: domeportModel.testPatternMode
                            onToggled: domeportModel.currentMode = checked
                                       ? "Test pattern"
                                       : inputSelector.currentBackend
                        }

                        // Shared multi-backend picker. Camera is intentionally
                        // omitted (DomeportPro has no camera capture). Selecting a
                        // backend drives currentMode; picking a source feeds the
                        // sourceName lifecycle. DOMEPORTPRO_BASIC collapses the
                        // list to video and image file only.
                        InputSourceSelector {
                            id: inputSelector
                            Layout.fillWidth: true
                            allowedBackends: domeportModel.basicFeatures
                                             ? ["Video file", "Image file"]
                                             : ["Video file", "Image file", "NDI", "Spout", "Syphon"]
                            sources: domeportModel.sourceList

                            onBackendSelected: name => { domeportModel.currentMode = name }
                            onSourceSelected: name => { domeportModel.sourceName = name }
                            onVideoFileSelected: path => { domeportModel.videoFilePath = path }
                            onImageFileSelected: path => { domeportModel.imageFilePath = path }
                            onRefreshRequested: () => Controller.updateSources()
                        }

                        // Transport: play/pause button and a scrub slider,
                        // shown only in Video file mode.
                        RowLayout {
                            visible: domeportModel.videoFileMode
                            Layout.fillWidth: true
                            spacing: Theme.spacing

                            CustomButton {
                                Layout.preferredWidth: 60
                                height: Theme.buttonHeight
                                text: domeportModel.running ? "Pause" : "Play"
                                onClicked: Controller.togglePause()
                            }

                            Slider {
                                id: transportSlider
                                Layout.fillWidth: true
                                from: 0.0
                                to: domeportModel.video.videoDurationMsec
                                value: domeportModel.video.playheadMsec
                                stepSize: 0.0
                                onMoved: domeportModel.video.playheadRequestMsec = value
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separatorColor }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing

                            CustomLabel { text: "Format" }

                            CustomComboBox {
                                id: formatSelector
                                Layout.fillWidth: true
                                model: domeportModel.formatList
                                onActivated: domeportModel.currentFormat = currentValue
                                Component.onCompleted: {
                                    let index = indexOfValue(domeportModel.currentFormat)
                                    if (index >= 0) {
                                        currentIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing

                            CustomLabel { text: "Zoom" }

                            CustomSpinBox {
                                id: zoomSpinBox
                                Layout.fillWidth: true
                                from: domeportModel.zoomMin
                                to: domeportModel.zoomMax
                                value: domeportModel.zoom
                                onValueModified: domeportModel.zoom = value
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.preferredHeight: Theme.padding }
                    }
                }

                // ---- Options tab ----
                ScrollView {
                    id: optionsScroll
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: optionsScroll.availableWidth - 2 * Theme.padding
                        x: Theme.padding
                        spacing: Theme.spacing

                        CustomLabel {
                            text: "Options"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeTitle
                            Layout.topMargin: Theme.padding
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing

                            CustomLabel { text: "Model" }

                            CustomComboBox {
                                id: modelSelector
                                Layout.fillWidth: true
                                model: domeportModel.modelList
                                onActivated: domeportModel.currentModel = currentValue
                                Component.onCompleted: {
                                    let index = indexOfValue(domeportModel.currentModel)
                                    if (index >= 0) {
                                        currentIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing

                            CustomLabel { text: "Camera FoV" }

                            CustomSpinBox {
                                id: cameraFovSpinBox
                                Layout.fillWidth: true
                                from: domeportModel.cameraFovMin
                                to: domeportModel.cameraFovMax
                                value: domeportModel.cameraFov
                                onValueModified: domeportModel.cameraFov = value
                            }
                        }

                        CustomSwitch {
                            text: "Fly mode"
                            checked: domeportModel.cameraFly
                            onToggled: Controller.setCameraFly(checked)
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separatorColor }

                        CustomSwitch {
                            id: debugSwitch
                            text: "Debug"
                        }

                        CustomSwitch {
                            text: "Dark mode"
                            checked: Theme.dark
                            onToggled: Theme.dark = checked
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separatorColor }

                        CustomButton {
                            Layout.fillWidth: true
                            text: "About"
                            onClicked: aboutDialog.open()
                        }

                        Item { Layout.fillHeight: true; Layout.preferredHeight: Theme.padding }
                    }
                }
            }
        }
    }

    // ---- About modal ----
    AboutDialog {
        id: aboutDialog
        appName: "Domeport Pro"
        appDetails: "Domemaster / equirectangular content visualizer for domes and planetariums in a 3D environment."
        logoPath: Qt.resolvedUrl("resources/images/DomeportPro.png")
        parentWindow: view.appWindow
    }
}
