import AppKit

setbuf(__stdoutp, nil)
print("[main] Starting Progressive Blur...")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
