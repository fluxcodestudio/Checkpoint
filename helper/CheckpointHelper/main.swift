import Cocoa

// Keep strong reference to delegate
let delegate = AppDelegate()

// Setup and run
let app = NSApplication.shared
app.delegate = delegate
app.run()
