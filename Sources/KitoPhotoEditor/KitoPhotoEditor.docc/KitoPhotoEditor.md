# ``KitoPhotoEditor``

Take a photo and edit it in SwiftUI with filters, adjustments, cropping, and text.

## Overview

KitoPhotoEditor pairs a full-screen camera with a photo editor. ``KitoCameraView``
provides a live preview with flash, zoom, a grid, and a front/back flip.
``KitoPhotoEditorView`` offers twelve filters with adjustable intensity, eight
adjustments, crop, rotate and flip, and draggable text; press and hold the photo
to compare it with the original.

``KitoPhotoFlow`` chains the two — camera, then editor — and hands back the
edited image:

```swift
KitoPhotoFlow { edited in
    publish(edited)
} onCancel: {
    dismiss()
}
```

Add `NSCameraUsageDescription` to your Info.plist. Without a camera, or when
access is denied as in the simulator, the camera offers a generated
``KitoSamplePhoto`` so the editor can still be tried.

To render without any UI, describe the edit as a ``KitoPhotoEdit`` — a
``KitoPhotoFilter`` and its intensity, ``KitoPhotoAdjustments``, a
``KitoCropAspect``, quarter turns and a flip — and pass it to
``KitoPhotoRenderer``. Everything is rendered with Core Image on one shared
context.

## Topics

### Essentials

- ``KitoPhotoFlow``
- ``KitoPhotoEditorView``

### Camera

- ``KitoCameraView``
- ``KitoCameraModel``
- ``KitoSamplePhoto``

### Edits and Rendering

- ``KitoPhotoEdit``
- ``KitoPhotoFilter``
- ``KitoPhotoAdjustments``
- ``KitoCropAspect``
- ``KitoPhotoText``
- ``KitoPhotoRenderer``
