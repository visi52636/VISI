# VISI – 360° Project Panoramas for iPhone

A native SwiftUI iPhone (and iPad) app to organise 360° panoramas into projects, view them
immersively, and share them with other devices.

## Features

- **Projects** – create, rename and delete projects; each holds any number of panoramas.
- **Upload** – add equirectangular 360° images (2:1, e.g. from Insta360, Ricoh Theta, GoPro Max,
  or the iPhone panorama exports) from **Photos** or the **Files** app. Originals are kept untouched.
- **360° viewer** (SceneKit)
  - drag to look around, pinch to zoom, double-tap / ⌖ to recenter
  - **motion mode**: move the phone to look around (gyroscope)
  - previous / next to walk through the panoramas of a project
- **Share with other devices**
  - **Share Project** exports the whole project as a single `.visiproj` file. Send it with
    AirDrop, Messages, Mail, or save it to iCloud Drive / Files. On another iPhone or iPad
    with VISI installed, tapping the file opens the app and imports the project automatically
    (or use the *Import* button on the Projects screen).
  - **Share Image** sends an individual original panorama to any app or device.

## Requirements

- Xcode 15 or newer, iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
xcodegen generate     # creates VISI.xcodeproj from project.yml
open VISI.xcodeproj
```

In Xcode select the **VISI** target → *Signing & Capabilities* → choose your Team, then run on
your iPhone. (Motion mode needs a real device; the simulator supports drag/pinch only.)

## Project layout

```
project.yml                      XcodeGen spec (Info.plist, .visiproj file type)
VISI/App/VISIApp.swift           App entry, handles opening received .visiproj files
VISI/Models/Models.swift         Project, Panorama, ProjectArchive (share format)
VISI/Services/ProjectStore.swift Storage in Documents/, import & export of projects
VISI/Services/ImageProcessing.swift  Thumbnails and GPU-safe downsampling
VISI/Views/                      SwiftUI screens and the SceneKit 360° renderer
```

Data lives in the app's Documents folder (`projects.json` + `Projects/<id>/` images) and is
also visible in the Files app under *On My iPhone › VISI*.

## Possible next steps

- iCloud / CloudKit sync so projects stay in sync automatically across your devices
- Hotspots linking panoramas into a virtual tour
- Web share link (upload to a server and view in any browser)
