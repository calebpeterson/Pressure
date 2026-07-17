import Foundation

final class CPUReader {
    private var previousUsageTicks: UInt32 = 0
    private var previousTotalTicks: UInt32 = 0

    func readCPUUsagePercent() -> Double? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t!
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )

        guard result == KERN_SUCCESS, let infoArray else {
            return nil
        }

        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<Int32>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }

        let loadInfo = infoArray.withMemoryRebound(
            to: processor_cpu_load_info_data_t.self,
            capacity: Int(cpuCount)
        ) {
            Array(UnsafeBufferPointer(start: $0, count: Int(cpuCount)))
        }

        var totalUsageTicks: UInt32 = 0
        var totalTicks: UInt32 = 0

        for core in loadInfo {
            let user = core.cpu_ticks.0
            let system = core.cpu_ticks.1
            let idle = core.cpu_ticks.2
            let nice = core.cpu_ticks.3

            totalUsageTicks += user &+ system &+ nice
            totalTicks += user &+ system &+ idle &+ nice
        }

        defer {
            previousUsageTicks = totalUsageTicks
            previousTotalTicks = totalTicks
        }

        guard previousTotalTicks > 0 else {
            return nil
        }

        let usageDelta = Double(totalUsageTicks &- previousUsageTicks)
        let totalDelta = Double(totalTicks &- previousTotalTicks)

        guard totalDelta > 0 else {
            return nil
        }

        return (usageDelta / totalDelta) * 100.0
    }
}

enum MemoryMetrics {
    static func readMemoryUsagePercent() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let usedBytes = Double(usedPages) * Double(pageSize)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

        guard totalBytes > 0 else {
            return nil
        }

        return (usedBytes / totalBytes) * 100.0
    }
}
