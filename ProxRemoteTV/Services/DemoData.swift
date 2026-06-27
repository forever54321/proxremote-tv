import Foundation

enum DemoData {
    static let nodeA = "pve-alpha"
    static let nodeB = "pve-beta"

    static func clusterResources() -> [ClusterResource] {
        [
            ClusterResource(
                type: "node", status: "online", name: nodeA, node: nodeA,
                vmid: nil, cpu: 0.18, maxcpu: 8,
                mem: 12 * 1024 * 1024 * 1024,
                maxmem: 32 * 1024 * 1024 * 1024,
                disk: nil, maxdisk: nil, uptime: 412800
            ),
            ClusterResource(
                type: "node", status: "online", name: nodeB, node: nodeB,
                vmid: nil, cpu: 0.34, maxcpu: 8,
                mem: 18 * 1024 * 1024 * 1024,
                maxmem: 32 * 1024 * 1024 * 1024,
                disk: nil, maxdisk: nil, uptime: 96000
            ),

            ClusterResource(
                type: "qemu", status: "running", name: "web-nginx", node: nodeA,
                vmid: 100, cpu: 0.04, maxcpu: 2,
                mem: 512 * 1024 * 1024,
                maxmem: 2 * 1024 * 1024 * 1024,
                disk: 8 * 1024 * 1024 * 1024,
                maxdisk: 32 * 1024 * 1024 * 1024,
                uptime: 96000
            ),
            ClusterResource(
                type: "qemu", status: "running", name: "db-postgres", node: nodeA,
                vmid: 101, cpu: 0.22, maxcpu: 4,
                mem: 4 * 1024 * 1024 * 1024,
                maxmem: 8 * 1024 * 1024 * 1024,
                disk: 38 * 1024 * 1024 * 1024,
                maxdisk: 128 * 1024 * 1024 * 1024,
                uptime: 96000
            ),
            ClusterResource(
                type: "qemu", status: "running", name: "media-jellyfin", node: nodeB,
                vmid: 110, cpu: 0.61, maxcpu: 4,
                mem: 6 * 1024 * 1024 * 1024,
                maxmem: 8 * 1024 * 1024 * 1024,
                disk: 18 * 1024 * 1024 * 1024,
                maxdisk: 64 * 1024 * 1024 * 1024,
                uptime: 64000
            ),
            ClusterResource(
                type: "qemu", status: "stopped", name: "dev-gitea", node: nodeB,
                vmid: 111, cpu: 0.0, maxcpu: 2,
                mem: 0,
                maxmem: 4 * 1024 * 1024 * 1024,
                disk: 0,
                maxdisk: 32 * 1024 * 1024 * 1024,
                uptime: 0
            ),

            ClusterResource(
                type: "lxc", status: "running", name: "homeassistant", node: nodeA,
                vmid: 200, cpu: 0.05, maxcpu: 2,
                mem: 700 * 1024 * 1024,
                maxmem: 2 * 1024 * 1024 * 1024,
                disk: 4 * 1024 * 1024 * 1024,
                maxdisk: 16 * 1024 * 1024 * 1024,
                uptime: 412800
            ),
            ClusterResource(
                type: "lxc", status: "running", name: "pihole", node: nodeA,
                vmid: 201, cpu: 0.01, maxcpu: 1,
                mem: 150 * 1024 * 1024,
                maxmem: 512 * 1024 * 1024,
                disk: 2 * 1024 * 1024 * 1024,
                maxdisk: 8 * 1024 * 1024 * 1024,
                uptime: 412800
            ),
            ClusterResource(
                type: "lxc", status: "running", name: "traefik", node: nodeB,
                vmid: 202, cpu: 0.02, maxcpu: 1,
                mem: 80 * 1024 * 1024,
                maxmem: 512 * 1024 * 1024,
                disk: 1 * 1024 * 1024 * 1024,
                maxdisk: 8 * 1024 * 1024 * 1024,
                uptime: 96000
            ),

            ClusterResource(
                type: "storage", status: "available", name: "local", node: nodeA,
                vmid: nil, cpu: nil, maxcpu: nil,
                mem: nil, maxmem: nil,
                disk: 28 * 1024 * 1024 * 1024,
                maxdisk: 100 * 1024 * 1024 * 1024,
                uptime: nil
            ),
            ClusterResource(
                type: "storage", status: "available", name: "local-zfs", node: nodeA,
                vmid: nil, cpu: nil, maxcpu: nil,
                mem: nil, maxmem: nil,
                disk: 380 * 1024 * 1024 * 1024,
                maxdisk: 2 * 1024 * 1024 * 1024 * 1024,
                uptime: nil
            ),
            ClusterResource(
                type: "storage", status: "available", name: "truenas-nfs", node: nodeB,
                vmid: nil, cpu: nil, maxcpu: nil,
                mem: nil, maxmem: nil,
                disk: 4 * 1024 * 1024 * 1024 * 1024,
                maxdisk: 12 * 1024 * 1024 * 1024 * 1024,
                uptime: nil
            ),
        ]
    }

    static func clusterTasks() -> [ClusterTask] {
        let now = Int(Date().timeIntervalSince1970)
        return [
            ClusterTask(
                upid: "UPID:pve-alpha:00001234:0042B0C1::vzdump:100:demo@pve:",
                type: "vzdump", node: nodeA, user: "demo@pve",
                starttime: now - 3600, endtime: now - 3540,
                status: "stopped", exitstatus: "OK"
            ),
            ClusterTask(
                upid: "UPID:pve-beta:00001235:0042B0C2::qmstart:110:demo@pve:",
                type: "qmstart", node: nodeB, user: "demo@pve",
                starttime: now - 7200, endtime: now - 7195,
                status: "stopped", exitstatus: "OK"
            ),
            ClusterTask(
                upid: "UPID:pve-alpha:00001236:0042B0C3::aptupdate:demo@pve:",
                type: "aptupdate", node: nodeA, user: "demo@pve",
                starttime: now - 86400, endtime: now - 86380,
                status: "stopped", exitstatus: "OK"
            ),
        ]
    }

    static func nodeStatus(node: String) -> NodeStatus {
        let dict: [String: Any] = [
            "uptime": node == nodeA ? 412800 : 96000,
            "kversion": "Linux 6.5.13-5-pve",
            "pveversion": "pve-manager/8.2.2/c4f3c0d5d0e",
            "cpu": node == nodeA ? 0.18 : 0.34,
            "cpuinfo": [
                "model": "Intel(R) Xeon(R) Silver 4214 CPU @ 2.20GHz",
                "cpus": 8,
            ],
            "memory": [
                "total": 32 * 1024 * 1024 * 1024,
                "used": (node == nodeA ? 12 : 18) * 1024 * 1024 * 1024,
                "free": (node == nodeA ? 20 : 14) * 1024 * 1024 * 1024,
            ],
            "swap": [
                "total": 8 * 1024 * 1024 * 1024,
                "used": 100 * 1024 * 1024,
            ],
            "rootfs": [
                "total": 100 * 1024 * 1024 * 1024,
                "used": 28 * 1024 * 1024 * 1024,
            ],
        ]
        return NodeStatus(from: dict)
    }

    static func vmConfig(vmid: Int, type: String) -> VMConfig {
        let name = vmName(vmid)
        let dict: [String: Any] = [
            "name": name,
            "cores": type == "qemu" ? 2 : 1,
            "sockets": 1,
            "memory": type == "qemu" ? 2048 : 1024,
            "ostype": type == "qemu" ? "l26" : "debian",
            "boot": "order=scsi0",
            "agent": "1",
            "net0": "virtio=AA:BB:CC:DD:EE:0\(vmid),bridge=vmbr0,firewall=1",
            "scsi0": "local-zfs:vm-\(vmid)-disk-0,size=32G",
        ]
        return VMConfig(from: dict)
    }

    static func vmStatus(vmid: Int, type: String, isRunning: Bool) -> [String: Any] {
        [
            "name": vmName(vmid),
            "status": isRunning ? "running" : "stopped",
            "vmid": vmid,
            "cpu": isRunning ? 0.05 : 0.0,
            "cpus": type == "qemu" ? 2 : 1,
            "mem": isRunning ? 700 * 1024 * 1024 : 0,
            "maxmem": 2 * 1024 * 1024 * 1024,
            "disk": 4 * 1024 * 1024 * 1024,
            "maxdisk": 16 * 1024 * 1024 * 1024,
            "uptime": isRunning ? 96000 : 0,
        ]
    }

    static func snapshots() -> [Snapshot] {
        let now = Int(Date().timeIntervalSince1970)
        return [
            Snapshot(
                name: "before-upgrade",
                description: "Snapshot before package upgrade",
                snaptime: now - 7 * 86400,
                parent: nil,
                vmstate: 0
            ),
            Snapshot(
                name: "baseline",
                description: "Clean install baseline",
                snaptime: now - 30 * 86400,
                parent: "before-upgrade",
                vmstate: 0
            ),
        ]
    }

    static func vmName(_ vmid: Int) -> String {
        switch vmid {
        case 100: return "web-nginx"
        case 101: return "db-postgres"
        case 110: return "media-jellyfin"
        case 111: return "dev-gitea"
        case 200: return "homeassistant"
        case 201: return "pihole"
        case 202: return "traefik"
        default: return "vm-\(vmid)"
        }
    }
}
