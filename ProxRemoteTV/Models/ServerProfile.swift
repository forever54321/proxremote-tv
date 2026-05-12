import Foundation

struct ServerProfile: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let host: String
    let port: Int
    let username: String
    let password: String
    let realm: String
    let trustSelfSigned: Bool

    var baseURL: String { "https://\(host):\(port)" }
}

struct ClusterResource: Codable, Identifiable, Hashable {
    let type: String       // node, qemu, lxc, storage
    let status: String     // running, stopped, online, offline
    let name: String
    let node: String
    let vmid: Int?
    let cpu: Double?
    let maxcpu: Int?
    let mem: Int?
    let maxmem: Int?
    let disk: Int?
    let maxdisk: Int?
    let uptime: Int?

    var id: String { "\(type)/\(vmid ?? 0)/\(name)" }

    var isNode: Bool { type == "node" }
    var isVM: Bool { type == "qemu" }
    var isContainer: Bool { type == "lxc" }
    var isStorage: Bool { type == "storage" }
    var isRunning: Bool { status == "running" || status == "online" }
    var isStopped: Bool { status == "stopped" || status == "offline" }

    var displayType: String {
        switch type {
        case "node": return "Node"
        case "qemu": return "VM"
        case "lxc": return "Container"
        case "storage": return "Storage"
        default: return type
        }
    }

    var cpuPercent: Double {
        guard let cpu = cpu else { return 0 }
        return cpu * 100
    }

    var memPercent: Double {
        guard let mem = mem, let maxmem = maxmem, maxmem > 0 else { return 0 }
        return Double(mem) / Double(maxmem) * 100
    }

    var diskPercent: Double {
        guard let disk = disk, let maxdisk = maxdisk, maxdisk > 0 else { return 0 }
        return Double(disk) / Double(maxdisk) * 100
    }
}

struct VMConfig: Codable {
    let name: String?
    let cores: Int?
    let sockets: Int?
    let memory: Int?
    let balloon: Int?
    let ostype: String?
    let boot: String?
    let agent: String?
    let net0: String?
    let scsi0: String?
    let ide2: String?

    init(from dict: [String: Any]) {
        name = dict["name"] as? String
        cores = dict["cores"] as? Int
        sockets = dict["sockets"] as? Int
        memory = dict["memory"] as? Int
        balloon = dict["balloon"] as? Int
        ostype = dict["ostype"] as? String
        boot = dict["boot"] as? String
        agent = dict["agent"] as? String
        net0 = dict["net0"] as? String
        scsi0 = dict["scsi0"] as? String
        ide2 = dict["ide2"] as? String
    }
}

struct Snapshot: Codable, Identifiable {
    let name: String
    let description: String?
    let snaptime: Int?
    let parent: String?
    let vmstate: Int?

    var id: String { name }
    var isCurrent: Bool { name == "current" }

    var formattedDate: String {
        guard let snaptime = snaptime else { return "Unknown" }
        let date = Date(timeIntervalSince1970: TimeInterval(snaptime))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct NodeStatus: Codable {
    let cpu: Double?
    let cpuModel: String?
    let cpuCores: Int?
    let memoryUsed: Int?
    let memoryTotal: Int?
    let swapUsed: Int?
    let swapTotal: Int?
    let rootfsUsed: Int?
    let rootfsTotal: Int?
    let uptime: Int?
    let kernelVersion: String?
    let pveVersion: String?

    init(from dict: [String: Any]) {
        cpu = dict["cpu"] as? Double
        let cpuInfo = dict["cpuinfo"] as? [String: Any]
        cpuModel = cpuInfo?["model"] as? String
        cpuCores = cpuInfo?["cpus"] as? Int
        let memInfo = dict["memory"] as? [String: Any]
        memoryUsed = memInfo?["used"] as? Int
        memoryTotal = memInfo?["total"] as? Int
        let swapInfo = dict["swap"] as? [String: Any]
        swapUsed = swapInfo?["used"] as? Int
        swapTotal = swapInfo?["total"] as? Int
        let rootfs = dict["rootfs"] as? [String: Any]
        rootfsUsed = rootfs?["used"] as? Int
        rootfsTotal = rootfs?["total"] as? Int
        uptime = dict["uptime"] as? Int
        kernelVersion = dict["kversion"] as? String
        pveVersion = dict["pveversion"] as? String
    }
}
