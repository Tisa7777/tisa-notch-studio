# Tisa Notch Studio

Tisa Notch Studio is a standalone macOS Photo Booth. Its first version includes a menu bar launcher, a panel that opens below the notch or menu bar, timed camera capture, and two vertical Khmer Heritage postage-stamp layouts.

## Run on a Mac

1. Extract the ZIP. Open `TisaNotch.xcodeproj` in Xcode.
2. Select the **Tisa Notch** scheme and **My Mac**, then press **⌘R**.
3. The photo booth opens below the notch or menu bar. To reopen it, click the camera aperture in the menu bar and choose **Open Photo Booth**.
4. Allow camera access. Choose **3 photos** or **4 photos**, set the timer to 3, 5, or 8 seconds, and click **Start**. Each photo gets its own countdown.
5. Click **Save PNG…** to choose where to save the finished stamp. Click **Take another** to start over.

The deployment target is macOS 14. The app uses Apple's AppKit, SwiftUI, AVFoundation, Core Graphics, Core Text, and Image I/O frameworks. It has no third-party packages or network permission. If Xcode requests a signing identity, choose a team under **Signing & Capabilities**.

## Camera and export

**Mirror front camera** is on by default for supported front cameras, including the Mac's built-in camera. The preview and captured photos use the same setting.

Closing the booth cancels a capture and stops the camera. Once a sequence completes, the camera stops and the booth displays the rendered stamp. Raw photos stay in memory during the sequence. The app writes only the finished PNG to the location you choose.

The 3-photo PNG is 1080 × 2259 pixels. The 4-photo PNG is 1080 × 2858 pixels. Both use a cream paper background, jade ink, Khmer text, a decorative postmark, and a transparent perforated edge. The editable app icon is in `Artwork/TisaNotchIcon.svg`. The stamp artwork is drawn by `TisaNotch/PostageStamp.swift`.

## Project scope

This standalone project was written from the feature brief. It uses a separate bundle ID and contains its own source and artwork. Version 0.1.0 covers the booth and stamp export. Music controls, clipboard history, and other features from the earlier app are outside this version's scope.
