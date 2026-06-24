import Foundation

// Entry point for the privileged helper daemon (`com.duoupdater.helper`). Runs as
// root under launchd, registered by the main app via `SMAppService.daemon`. It
// hosts an XPC listener on the Mach service declared in the daemon plist,
// validates each connecting client's code signature (see HelperService), and
// vends `MASHelperProtocol`.
//
// No osascript, no password: the app sends a structured install request, the
// helper (already root) runs `mas install` and streams progress to a log file the
// app tails. The whole reason this process exists is to be the one-time-approved
// root that replaces the per-install authorization prompt.

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperService.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
