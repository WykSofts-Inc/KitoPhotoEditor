# KitoPhotoEditor

Take a photo and edit it in SwiftUI: a camera with flash, zoom and flip, twelve filters with
intensity, eight adjustments, crop, rotate and flip, and draggable text. Press and hold the photo to
compare it with the original. Part of the [Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

## Camera to editor in one view

```swift
KitoPhotoFlow { edited in
    publish(edited)          // your caption, upload or share screen
} onCancel: { dismiss() }
```

Add `NSCameraUsageDescription` to your Info.plist. Without a camera (or with access denied, as in
the simulator) the camera offers a generated sample photo, so you can still try the editor.

## Just the pieces

```swift
KitoCameraView(onCapture: { image in … }, onCancel: { … })
KitoPhotoEditorView(image: photo, onCancel: { … }, onDone: { edited in … })
```

## Rendering without UI

```swift
var edit = KitoPhotoEdit()
edit.filter = .film
edit.intensity = 0.8
edit.adjustments.warmth = 0.3
edit.adjustments.vignette = 0.5
edit.crop = .portrait            // .original, .square, .portrait (4:5), .landscape (16:9), .story (9:16)
edit.quarterTurns = 1            // clockwise
let result = KitoPhotoRenderer.render(photo, edit: edit)
```

Filters: `.original`, `.vivid`, `.warm`, `.cool`, `.mono`, `.noir`, `.fade`, `.chrome`, `.instant`,
`.dramatic`, `.sepia`, `.film`. Adjustments: exposure, brightness, contrast, saturation and warmth
(-1…1); vignette, sharpness and grain (0…1). Everything is Core Image on one shared context.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoPhotoEditor.git", from: "0.1.0")
```

## License

MIT — see [LICENSE](LICENSE).
