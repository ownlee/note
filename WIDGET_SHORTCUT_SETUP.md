# Widget and Shortcuts

Open `BrainNote.xcodeproj` and run the **BrainNote** scheme. The project contains:

- `BrainNote`: the main iOS app target.
- `BrainNoteWidget`: the embedded Widget Extension target.
- The `brainnote://capture` URL scheme used by Quick Capture.

## Add the widget in Simulator

1. Run the BrainNote scheme once so iOS registers the embedded extension.
2. Return to the Home Screen and touch and hold an empty area.
3. Tap **Edit > Add Widget**, search for **BrainNote**, and choose Small or Medium.

The widget opens `brainnote://capture`. `ContentView` returns to **For You** and
moves focus directly to the scratchpad input.

## App Shortcuts

The main app target includes two shortcuts:

- **Capture a Thought**: accepts text and saves it without opening the app.
- **Open Quick Capture**: opens the app with the scratchpad focused.

No App Group is required for this widget because it launches the app instead of
reading the SwiftData store from the extension.
