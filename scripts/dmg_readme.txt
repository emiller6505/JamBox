JamBox — first launch
=====================

1. Drag JamBox.app to the Applications folder (use the
   shortcut in this window).

2. The first time you open JamBox, macOS will block it with
   a message like "JamBox cannot be opened because Apple
   cannot check it for malicious software."

   This happens because JamBox is not signed by a paid
   Apple Developer account. The app is safe; the warning
   is just Gatekeeper doing its job.

   To open it, pick ONE of these:

   --- Option A: Terminal (fastest) ---

   Open Terminal and run:

       xattr -dr com.apple.quarantine /Applications/JamBox.app

   Then double-click JamBox normally.

   --- Option B: System Settings ---

   1. Double-click JamBox.app and dismiss the warning.
   2. Open System Settings -> Privacy & Security.
   3. Scroll down. You should see a message about JamBox
      being blocked, with an "Open Anyway" button.
   4. Click "Open Anyway" and confirm.

3. After the first launch, JamBox opens like any other app.
   You only have to do this once.
