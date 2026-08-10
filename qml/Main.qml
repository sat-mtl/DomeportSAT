import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick3D
import QtQuick3D.Helpers

import Score.UI as UI
import domeportpro

Window {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "Domeport Pro"
    color: "#1a1a2e"

    property bool running: true

    Item {
        id: domeportModel

        QtObject { id: rotateZoom
            property var process_object : Score.find("rotate_zoom");
            property var zoom : Score.inlet(process_object, 4);
        }

        QtObject { id: formatMixer
            property var process_object : Score.find("Video Mixer.1")
            property var alpha1 : Score.inlet(process_object, 8);
            property var alpha2 : Score.inlet(process_object, 9);

            function enableEquirectangular() {
                Score.setValue(alpha1, 1.0)
                Score.setValue(alpha2, 0.0)
            }

            function enableDomemaster() {
                Score.setValue(alpha1, 0.0)
                Score.setValue(alpha2, 1.0)
            }

        }

        QtObject { id: equirectangularToDomemaster
            property var process_object : Score.find("equirectangular_to_domemaster");
            property var domemaster_master_output_fov_degrees : Score.inlet(process_object, 2);
        }

        QtObject { id: videoMixer
            property var process_object : Score.find("Video Mixer");
            property var alpha1 : Score.inlet(process_object, 8);
            property var alpha2 : Score.inlet(process_object, 9);
            property var alpha3 : Score.inlet(process_object, 10);
            property var alpha4 : Score.inlet(process_object, 11);
        }

        QtObject { id: video
            property var process_object : Score.find("Video");
            property double videoDurationMsec: 0.0;
            onVideoDurationMsecChanged: {
                // resize interval to video duration
                Score.setIntervalDuration(Score.rootInterval(), Util.timevalFromMilliseconds(videoDurationMsec))
            }

            property double playheadRequestMsec: 0.0;
            onPlayheadRequestMsecChanged: {
                Score.scrub(playheadRequestMsec)
            }

            property double playheadMsec: 0.0;

            function onLoopDurationChanged(loopDuration) {
                const loopDurationMsec = Util.toMilliseconds(loopDuration)
                videoDurationMsec = loopDurationMsec
            }

            function onPositionChanged(position) {
                playheadMsec = videoDurationMsec * position % videoDurationMsec
            }

            Component.onCompleted: {
                process_object.loopDurationChanged.connect(onLoopDurationChanged)
                Score.rootInterval().durations.positionChanged.connect(onPositionChanged)
            }
        }

        QtObject { id: test_pattern
            property var process_object : Score.find("test_pattern");
            property var index : Score.inlet(process_object, 0);
            function setIndex(newIndex) {
                Score.setValue(index, newIndex)
            }
        }

        QtObject { id: image
            property var process_object : Score.find("image");
            property var path : Score.inlet(process_object, 5);
            function setPath(newPath) {
                Score.setValue(path, newPath)
            }
        }

        property bool basicFeatures: false
        property var modeList:
            if (basicFeatures) {
                [
                "Test pattern",
                "Image",
                "Video playback",
                ]
            }
            else if (Qt.platform.os === "windows") {
                [
                "Test pattern",
                "Image",
                "Video playback",
                "NDI",
                "Spout",
                ]
            } else if (Qt.platform.os === "osx") {
                [
                "Test pattern",
                "Image",
                "Video playback",
                "NDI",
                "Syphon",
                ]
            } else {
                [
                "Test pattern",
                "Image",
                "Video playback",
                "NDI",
                ]
            }

        property string currentMode: "Test pattern"
        onCurrentModeChanged: {
            console.log("changed mode: " + currentMode)
            modeSelector.currentIndex = modeSelector.indexOfValue(domeportModel.currentMode)
            removeLiveInput()
            if (currentMode === "Test pattern") {
                displayTestPattern()
            } else if (currentMode === "Image") {
                displayImage()
            } else if (currentMode === "Video playback") {
                displayVideoPlayback()
            } else if (currentMode === "NDI") {
                updateSources()
                sourceName = ndiSourceName
                if (ndiSourceName !== "") { createNDIInput(ndiSourceName) }
                displayLiveSource()
            } else if (currentMode === "Spout") {
                sourceName = spoutSourceName
                updateSources()
                if (spoutSourceName !== "") { createSpoutInput(spoutSourceName) }
                displayLiveSource()
            } else if (currentMode === "Syphon") {
                sourceName = syphonSourceName
                updateSources()
                if (syphonSourceName !== "") { createSyphonInput(syphonSourceName) }
                displayLiveSource()
            }
        }
        property bool testPatternMode: currentMode === "Test pattern"
        property bool imageMode: currentMode === "Image"
        property bool videoPlaybackMode: currentMode === "Video playback"
        property bool ndiMode: currentMode === "NDI"
        property bool spoutMode: currentMode === "Spout"
        property bool syphonMode: currentMode === "Syphon"
        property bool liveMode: ndiMode || spoutMode || syphonMode

        property var sourceList: [ "" ]
        property string sourceName: ""
        onSourceNameChanged: {
            if (currentMode === "NDI") {
                ndiSourceName = sourceName
            } else if (currentMode === "Spout") {
                spoutSourceName = sourceName
            } else if (currentMode === "Syphon") {
                syphonSourceName = sourceName
            }
        }

        property var ndiNamesList: [ "NDI sources..." ]

        property var spoutNamesList: [ "Spout sources..." ]

        property var syphonList: []
        property var syphonNamesList: [ "Syphon sources..." ]

        property string ndiSourceName: ""
        onNdiSourceNameChanged: {
            if (ndiSourceName !== "") {
                console.log("updated NDI Source Name: " + ndiSourceName)
                removeLiveInput()
                createNDIInput(ndiSourceName)
            }
        }

        property string spoutSourceName: ""
        onSpoutSourceNameChanged: {
            if (spoutSourceName !== "") {
                console.log("updated Spout Source Name: " + spoutSourceName)
                removeLiveInput()
                createSpoutInput(spoutSourceName)
            }
        }

        property string syphonSourceName: ""
        onSyphonSourceNameChanged: {
            if (syphonSourceName !== "") {
                console.log("updated Syphon Source Name: " + syphonSourceName)
                removeLiveInput()
                createSyphonInput(syphonSourceName)
            }
        }

        property double zoomMin: 1
        property double zoomMax: 200
        property double zoom: 100
        onZoomChanged: {
            if (currentFormat === "Domemaster") {
                Score.setValue(rotateZoom.zoom, zoom / 100)
            } else if (currentFormat === "Equirectangular") {
                let zoomedFov = currentModelFov / (zoom / 100)
                if (zoomedFov < 360) {
                    Score.setValue(equirectangularToDomemaster.domemaster_master_output_fov_degrees, zoomedFov)
                    Score.setValue(rotateZoom.zoom, 1)
                } else {
                    // treat as domemaster over 360 fov, so texture does not repeat
                    Score.setValue(equirectangularToDomemaster.domemaster_master_output_fov_degrees, 360)
                    let zoomFactor = 360 / zoomedFov
                    Score.setValue(rotateZoom.zoom, zoomFactor)
                }
            }
        }

        property double cameraFovMin: 45.0
        property double cameraFovMax: 120.0
        property double cameraFov: 90.0
        property bool cameraFly: false

        property string imageFilePath: ""
        onImageFilePathChanged: {
            console.log("imageFilePath: " + imageFilePath)
            if (imageFilePath === "") return
            Score.stop()
            image.setPath(imageFilePath)
            Score.play()
        }

        property string videoFilePath: ""
        onVideoFilePathChanged: {
            console.log("videoFilePath: " + videoFilePath)
            if (videoFilePath === "") return
            Score.stop()
            video.process_object.path = videoFilePath
            Score.play()
        }

        property var formatList: ["Equirectangular", "Domemaster"]
        property string currentFormat: "Equirectangular"
        onCurrentFormatChanged: {
            console.log("changed format: " + currentFormat)
            if (currentFormat === "Equirectangular") {
                test_pattern.setIndex(0)
                formatMixer.enableEquirectangular()
            } else if (currentFormat === "Domemaster") {
                test_pattern.setIndex(1)
                formatMixer.enableDomemaster()
            }
        }

        property var modelList: ["210 degrees", "180 degrees"]
        property string currentModel: "210 degrees"
        property real currentModelFov: 210
        onCurrentModelChanged: {
            console.log("changed model: " + currentModel)
            if (currentModel === "210 degrees") {
                currentModelFov = 210
                load210DegreesModel()
            } else if (currentModel === "180 degrees") {
                currentModelFov = 180
                load180DegreesModel()
            }
        }
    }

    function load210DegreesModel() {
        dome.source = "sato210.mesh"
        Score.setValue(equirectangularToDomemaster.domemaster_master_output_fov_degrees, 210.0)
    }

    function load180DegreesModel() {
        dome.source = "sato180.mesh"
        Score.setValue(equirectangularToDomemaster.domemaster_master_output_fov_degrees, 180.0)
    }

    function ndiAdded(factory, category, name, settings) {
        console.log("NDI added: " + name)
        const index = domeportModel.ndiNamesList.indexOf(name)
        if (index === -1) {
            domeportModel.ndiNamesList.push(name)
        }
    }

    function ndiRemoved(factory, name) {
        console.log("NDI removed: " + name)
        const index = domeportModel.ndiNamesList.indexOf(name)
        if (index !== -1) {
            domeportModel.ndiNamesList.splice(index, 1);
        }
     }

    function registerNDIListener() {
        try {
            let ndiEnumerator = Score.enumerateDevices("ae78b7c6-6400-483e-b45b-fd6ff87ec700")
            ndiEnumerator.deviceAdded.connect(ndiAdded)
            ndiEnumerator.deviceRemoved.connect(ndiRemoved)
            ndiEnumerator.enumerate = true
        } catch (error) {
            console.log("Error registering NDI listener: " + error)
        }
    }

    function spoutAdded(factory, category, name, settings) {
        console.log("Spout added: " + name)
        const index = domeportModel.spoutNamesList.indexOf(name)
        if (index !== 1) {
            domeportModel.spoutNamesList.push(name)
        }
    }

    function enumerateSpout() {
        domeportModel.spoutNamesList = [ "Spout sources..." ]
        try {
            let spoutEnumerator = Score.enumerateDevices("3c995cb6-052b-4c52-a8fd-841b33b81b29")
            spoutEnumerator.deviceAdded.connect(spoutAdded)
            spoutEnumerator.enumerate = true
        } catch (error) {
            console.log("Error enumerating Spout sources: " + error)
        }
    }

    function enumerateSyphon() {
        domeportModel.syphonList = []
        domeportModel.syphonNamesList = [ "Syphon sources..." ]
        try {
            let syphonEnumerator = Score.enumerateDevices("398cec01-c4ea-43b7-8281-d848748e0f68")
            syphonEnumerator.enumerate = true
            for (let dev of syphonEnumerator.devices) {
                domeportModel.syphonList.push(dev)
                domeportModel.syphonNamesList.push(dev.name)
                console.log("Syphon added: " + dev.name)
            }
        } catch (error) {
            console.log("Error enumerating Syphon sources: " + error)
        }
    }

    function updateSources() {
        if (domeportModel.currentMode === "NDI") {
            domeportModel.sourceList = domeportModel.ndiNamesList
        } else if (domeportModel.currentMode === "Spout") {
            enumerateSpout()
            domeportModel.sourceList = domeportModel.spoutNamesList
        } else if (domeportModel.currentMode === "Syphon") {
            enumerateSyphon()
            domeportModel.sourceList = domeportModel.syphonNamesList
        }
    }

    function displayTestPattern() {
        Score.setValue(videoMixer.alpha1, 1.0)
        Score.setValue(videoMixer.alpha2, 0.0)
        Score.setValue(videoMixer.alpha3, 0.0)
        Score.setValue(videoMixer.alpha4, 0.0)
        Score.play()
    }

    function displayImage() {
        Score.setValue(videoMixer.alpha1, 0.0)
        Score.setValue(videoMixer.alpha2, 1.0)
        Score.setValue(videoMixer.alpha3, 0.0)
        Score.setValue(videoMixer.alpha4, 0.0)
        Score.play()
    }

    function displayVideoPlayback() {
        Score.setValue(videoMixer.alpha1, 0.0)
        Score.setValue(videoMixer.alpha2, 0.0)
        Score.setValue(videoMixer.alpha3, 1.0)
        Score.setValue(videoMixer.alpha4, 0.0)
        Score.play()
    }

    function displayLiveSource() {
        Score.setValue(videoMixer.alpha1, 0.0)
        Score.setValue(videoMixer.alpha2, 0.0)
        Score.setValue(videoMixer.alpha3, 0.0)
        Score.setValue(videoMixer.alpha4, 1.0)
        Score.play()
    }

    function removeLiveInput() {
        Score.stop()
        try { Score.removeDevice("live_input"); } catch(_) {}
    }

    function createNDIInput(name) {
        console.log("Create NDI input: " + name)
        Score.stop()

        // create a NDI source
        let settings = {
            "Path": name
        }
        Score.createDevice("live_input", "ae78b7c6-6400-483e-b45b-fd6ff87ec700", settings)

        // attach NDI source to image inlet
        let liveSource = Score.find("live_source")
        let liveSourceInlet = Score.port(liveSource, "inputImage")
        Score.setAddress(liveSourceInlet, "live_input:/")

        console.log("Created NDI input: " + name)
        Score.play()
    }

    function createSpoutInput(name) {
        console.log("Create Spout input: " + name)
        Score.stop()

        // create a Spout source
        let settings = {
            "Path": name
        }
        Score.createDevice("live_input", "3c995cb6-052b-4c52-a8fd-841b33b81b29", settings)

        // attach Spout source to image inlet
        let liveSource = Score.find("live_source")
        let liveSourceInlet = Score.port(liveSource, "inputImage")
        Score.setAddress(liveSourceInlet, "live_input:/")

        console.log("Created Spout input: " + name)
        Score.play()
    }

    function createSyphonInput(name) {
        console.log("Create Syphon input: " + name)
        Score.stop()

        // create a Syphon source
        const index = domeportModel.syphonNamesList.indexOf(name)
        const settings = domeportModel.syphonList[index - 1].settings
        Score.createDevice("live_input", "398cec01-c4ea-43b7-8281-d848748e0f68", settings)

        // attach Syphon source to image inlet
        let liveSource = Score.find("live_source")
        let liveSourceInlet = Score.port(liveSource, "inputImage")
        Score.setAddress(liveSourceInlet, "live_input:/")

        console.log("Created Syphon input: " + name)
        Score.play()
    }

    function toggleCameraFlyMode() {
        if (domeportModel.cameraFly) {
            domeportModel.cameraFly = false
            camera.position.y = camera.cameraHeight
        } else {
            domeportModel.cameraFly = true
        }
    }

    function toggleTransport() {
        if (running) {
            console.log("stopping...")
            Score.stop()
        } else {
            console.log("starting...")
            Score.play()
        }
    }

    function togglePause() {
        if (running) {
            console.log("pausing...")
            Score.pause()
        } else {
            console.log("unpausing...")
            Score.play()
        }
    }

    function onPlay() {
        console.log("onPlay")
        transportButton.text = "Stop"
        pauseButton.text = "Pause"
        running = true
    }

    function onStop() {
        console.log("onStopped")
        transportButton.text = "Play"
        running = false
    }

    function onPause() {
        console.log("onPause")
        transportButton.text = "Play"
        pauseButton.text = "Unpause"
        running = false
    }

    function initialize() {
        const domeportProBasic = Util.environmentVariable("DOMEPORTPRO_BASIC")
        if (domeportProBasic) {
            domeportModel.basicFeatures = true
            console.log("Basic features enabled")
        }

        Score.transport().play.connect(onPlay)
        Score.transport().stop.connect(onStop)
        Score.transport().pause.connect(onPause)
        registerNDIListener()
        Score.play()
    }

    Component.onCompleted: {
        initialize()
    }

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
                            source: "GridBlack.jpg"
                            generateMipmaps: true 
                            mipFilter: Texture.Linear
                        }
                    }
                    shadingMode: CustomMaterial.Unshaded
                    vertexShader: "groundshader.vert"
                    fragmentShader: "groundshader.frag"
                }

            ]
        }

        Model {
            id: dome
            source: "sato210.mesh"
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
                    vertexShader: "domeshader.vert"
                    fragmentShader: "domeshader.frag"
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
        width: 4096 / (root.screen ? root.screen.devicePixelRatio : 1)
        height: 4096 / (root.screen ? root.screen.devicePixelRatio : 1)
        process: "rotate_zoom"
        port: 0
        visible: false
    }

    RowLayout {
        id: topRow
        anchors.top: parent.top
        width: parent.width - 2 * 12
        x: 12
        spacing: 12

        RowLayout {
            id: modeControls
            Layout.alignment: Qt.AlignLeft

            Label {
                id: modeSelectorLabel
                text: "Input\nMode"
                horizontalAlignment: Text.AlignHCenter
                color: "#FFFFFF"
            }

            ComboBox {
                id: modeSelector
                model: domeportModel.modeList
                onActivated: domeportModel.currentMode = currentValue
                Component.onCompleted: {
                    let index = indexOfValue(domeportModel.currentMode)
                    if (index >=0) {
                        currentIndex = index
                    }
                }
            }

        }

        RowLayout {
            id: sourceControls
            Layout.alignment: Qt.AlignLeft
            visible: domeportModel.liveMode

            Label {
                id: sourceSelectorLabel
                text: "Available\nSources"
                horizontalAlignment: Text.AlignHCenter
                color: "#FFFFFF"
            }

            ComboBox {
                id: sourceSelector
                Layout.preferredWidth: 180
                model: domeportModel.sourceList
                onActivated: {
                    domeportModel.sourceName = currentText
                    currentIndex = 0
                }
                onDownChanged: {
                    if (down && pressed) {
                        updateSources()
                        model = domeportModel.sourceList
                    }
                }
            }

            Label {
                id: sourceNameLabel
                text: "Current\nSource"
                horizontalAlignment: Text.AlignHCenter
                color: "#FFFFFF"
            }

            TextField {
                id: sourceNameTextField
                text: domeportModel.sourceName
                onEditingFinished: {
                    domeportModel.sourceName = text
                }
                visible: domeportModel.liveMode
            }
        }

        RowLayout {
            id: configControls
            Layout.alignment: Qt.AlignRight

            Label {
                id: formatLabel
                text: "Format"
                color: "#FFFFFF"
            }

            ComboBox {
                id: formatSelector
                model: domeportModel.formatList
                onActivated: domeportModel.currentFormat = currentValue
                Component.onCompleted: {
                    let index = indexOfValue(domeportModel.currentFormat)
                    if (index >=0) {
                        currentIndex = index
                    }
                }
            }

            Label {
                id: modelSelectorLabel
                text: "Model"
                color: "#FFFFFF"
            }

            ComboBox {
                id:  modelSelector
                model: domeportModel.modelList
                onActivated: domeportModel.currentModel = currentValue
                Component.onCompleted: {
                    let index = indexOfValue(domeportModel.currentModel)
                    if (index >=0) {
                        currentIndex = index
                    }
                }
            }

            Label {
                id: zoomLabel
                text: "Zoom"
                horizontalAlignment: Text.AlignHCenter
                color: "#FFFFFF"
            }

            SpinBox {
                id: zoomSpinBox
                Layout.preferredWidth: 55
                from: domeportModel.zoomMin
                to: domeportModel.zoomMax
                value: domeportModel.zoom
                onValueModified: {
                    domeportModel.zoom = value
                }
                editable: true
            }

            Label {
                id: cameraFovLabel
                text: "Camera\nFoV"
                horizontalAlignment: Text.AlignHCenter
                color: "#FFFFFF"
            }

            SpinBox {
                id: cameraFovSpinBox
                Layout.preferredWidth: 50
                from: domeportModel.cameraFovMin
                to: domeportModel.cameraFovMax
                value: domeportModel.cameraFov
                onValueModified: {
                    domeportModel.cameraFov = value
                }
                editable: true
            }

            Button {
                id: flyButton
                text: { domeportModel.cameraFly ? "Walk" : "Fly" }
                Layout.preferredWidth: 50
                onClicked: toggleCameraFlyMode()
            }

            Button {
                id: transportButton
                visible: true
                text: "Stop"
                Layout.preferredWidth: 50
                onClicked: toggleTransport()
            }

            Button {
                text: "Debug"
                Layout.preferredWidth: 50
                Layout.alignment: Qt.AlignRight
                onClicked: debugView.visible = !debugView.visible
                DebugView {
                    id: debugView
                    source: view3d
                    visible: false
                    anchors.top: parent.bottom
                    anchors.right: parent.right
                }
            }

        }

    }

    RowLayout {
        id: playbackControls
        anchors.bottom: parent.bottom
        width: parent.width - 2 * 12
        x: 12
        spacing: 12
        

        Button {
            id: browseImageButton
            text: "Browse..."
            Layout.preferredWidth: 60
            onClicked: imageFileDialog.open()
            visible: domeportModel.imageMode
        }

        Button {
            id: browseVideoButton
            text: "Browse..."
            Layout.preferredWidth: 60
            onClicked: videoFileDialog.open()
            visible: domeportModel.videoPlaybackMode
        }

        Text {
            id: videoFilePathLabel
            text: domeportModel.videoFilePath
            elide: Text.ElideLeft
            Layout.preferredWidth: 200
            color: "#FFFFFF"
            visible: domeportModel.videoPlaybackMode
        }

        Slider {
            id: transportSlider
            Layout.fillWidth: true
            from: 0.0
            to: video.videoDurationMsec
            value: video.playheadMsec
            stepSize: 0.0
            onMoved: {
                video.playheadRequestMsec = value
            }
            visible: domeportModel.videoPlaybackMode
        }

        Button {
            id: pauseButton
            text: "Pause"
            Layout.preferredWidth: 60
            onClicked: togglePause()
            visible: domeportModel.videoPlaybackMode
        }

    }

    FileDialog {
        id: videoFileDialog
        title: "Select Video File"
        nameFilters: ["Video Files (*.mkv *.mov *.mp4 *.h264 *.avi *.hap *.mpg *.mpeg *.imf *.mxf *.mts *.m2ts *.mj2 *.webm)", "All Files (*)"]
        onAccepted: {
            if (!selectedFile) return
            var filePath = new URL(selectedFile).pathname.substr(Qt.platform.os === "windows" ? 1 : 0);
            domeportModel.videoFilePath = filePath
        }
    }

    FileDialog {
        id: imageFileDialog
        title: "Select Image File"
        nameFilters: ["Image Files (*.jpg *.jpeg *.png *.gif)", "All Files (*)"]
        onAccepted: {
            if (!selectedFile) return
            var filePath = new URL(selectedFile).pathname.substr(Qt.platform.os === "windows" ? 1 : 0);
            domeportModel.imageFilePath = filePath
        }
    }

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        property var imageExtensions: [ ".jpg", ".jpeg", ".png", ".gif" ]
        property var videoExtensions: [ ".mkv", ".mov", ".mp4", ".h264", ".avi", ".hap", ".mpg", ".mpeg", ".imf", ".mxf", ".mts", ".m2ts", ".mj2", ".webm" ]
        onDropped: (drop) => {
            if (drop.hasUrls) {
                var filePath = new URL(drop.urls[0]).pathname.substr(Qt.platform.os === "windows" ? 1 : 0);
                if (imageExtensions.some(extension => filePath.endsWith(extension))) {
                    console.log("Dropped image file: ", filePath)
                    domeportModel.imageFilePath = filePath
                    domeportModel.currentMode = "Image"
                }
                if (videoExtensions.some(extension => filePath.endsWith(extension))) {
                    console.log("Dropped video file: ", filePath)
                    domeportModel.videoFilePath = filePath
                    domeportModel.currentMode = "Video playback"
                }
            }
        }
    }
}
