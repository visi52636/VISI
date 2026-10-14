# VIS X – 360° Project Panoramas for iPhone

A native SwiftUI iPhone (and iPad) app to organise 360° panoramas into projects, see where each
one was taken on a layout / floor plan, view them immersively, and share them with other devices.

## Features

- **Projects** – create, rename and delete projects; each holds any number of panoramas.
- **Upload** – add equirectangular 360° images (2:1, e.g. Insta360, Ricoh Theta, GoPro Max)
  from **Photos** or the **Files** app. Originals are kept untouched.
- **Layout (floor plan / site plan)**
  - add a layout per project from Photos or Files – images **or PDF drawings** (first page is used)
  - **Place** mode: pick a panorama and tap where it was taken; drag markers to adjust,
    long-press a thumbnail to remove it from the plan
  - numbered markers match the numbers on the panorama thumbnails
  - pinch or use +/− to zoom into large plans; tap a marker to open that 360° view
- **360° viewer** (SceneKit)
  - drag to look around, pinch to zoom, double-tap / ⌖ to recenter
  - **motion mode**: move the phone to look around (gyroscope)
  - **mini-map** of the layout showing your current position – tap another marker to jump
    there; expand it for a bigger view, or hide it with the map button
  - previous / next to walk through the project's panoramas
- **Share with other devices**
  - **Share Project** exports the whole project – panoramas, layout and positions – as one
    `.visx` file. Send it with AirDrop, Messages, Mail, or save it to iCloud Drive / Files.
    On another iPhone or iPad with VIS X installed, tapping the file imports the project
    (or use the *Import* button on the Projects screen).
  - **Share Image** sends an individual original panorama to any app or device.

## Requirements

- Xcode 15 or newer, iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
xcodegen generate     # creates VISX.xcodeproj from project.yml
open VISX.xcodeproj
```

In Xcode select the **VISX** target → *Signing & Capabilities* → choose your Team, then run on
your iPhone. (Motion mode needs a real device; the simulator supports drag/pinch only.)

## Project layout

```
project.yml                         XcodeGen spec (Info.plist, .visx file type)
VISX/App/VISXApp.swift              App entry, handles opening received .visx files
VISX/Models/Models.swift            Project, Panorama, LayoutPoint, ProjectArchive (share format)
VISX/Services/ProjectStore.swift    Storage in Documents/, layout, import & export of projects
VISX/Services/ImageProcessing.swift Thumbnails, GPU-safe downsampling, PDF plan rendering
VISX/Views/LayoutViews.swift        Layout canvas, placement mode, viewer mini-map
VISX/Views/                         Other SwiftUI screens and the SceneKit 360° renderer
```

Data lives in the app's Documents folder (`projects.json` + `Projects/<id>/` images) and is
also visible in the Files app under *On My iPhone › VIS X*.

## Possible next steps

- Viewing-direction cone on the mini-map (needs a per-panorama "north" calibration)
- iCloud / CloudKit sync so projects stay in sync automatically across devices
- Hotspots inside a panorama linking to neighbouring panoramas (virtual tour)
