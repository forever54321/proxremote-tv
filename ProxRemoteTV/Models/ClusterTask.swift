import Foundation

struct ClusterTask: Identifiable, Hashable {
    let upid: String
    let type: String
    let node: String
    let user: String
    let starttime: Int
    let endtime: Int?
    let status: String?
    let exitstatus: String?

    var id: String { upid }

    var isRunning: Bool { endtime == nil }
    var isFailed: Bool {
        if let s = exitstatus { return s != "OK" }
        return false
    }
    var isOK: Bool { exitstatus == "OK" }

    var displayType: String {
        switch type {
        case "vzdump": return "Backup"
        case "qmstart": return "VM Start"
        case "qmstop": return "VM Stop"
        case "qmshutdown": return "VM Shutdown"
        case "qmrestore": return "VM Restore"
        case "qmclone": return "VM Clone"
        case "qmigrate": return "VM Migrate"
        case "vzstart": return "CT Start"
        case "vzstop": return "CT Stop"
        case "vzshutdown": return "CT Shutdown"
        case "aptupdate": return "Package Update"
        case "srvreload": return "Service Reload"
        default: return type
        }
    }

    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(starttime)) }
}
