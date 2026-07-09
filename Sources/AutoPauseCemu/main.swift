import AutoPauseCore
import Darwin
import Foundation

private struct Options {
    enum Mode { case monitor, report, resume }

    var interval: TimeInterval = 2
    var anyGamepad = false
    var mode = Mode.monitor
    var verbose = false

    static func parse(_ arguments: [String]) throws -> Options {
        var result = Options()
        var arguments = arguments[...]

        while let argument = arguments.popFirst() {
            switch argument {
            case "--interval":
                guard let text = arguments.popFirst() else {
                    throw CLIError("--interval 缺少参数")
                }
                guard let seconds = Double(text), seconds >= 0.2 else {
                    throw CLIError("--interval 必须至少为 0.2 秒")
                }
                result.interval = seconds
            case "--any-gamepad":
                result.anyGamepad = true
            case "--once":
                result.mode = try result.mode.setting(.report)
            case "--resume-managed":
                result.mode = try result.mode.setting(.resume)
            case "--verbose":
                result.verbose = true
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                throw CLIError("未知参数：\(argument)")
            }
        }
        return result
    }
}

private extension Options.Mode {
    func setting(_ newMode: Self) throws -> Self {
        guard self == .monitor else {
            throw CLIError("--once 和 --resume-managed 不能同时使用")
        }
        return newMode
    }
}

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func printHelp() {
    print("""
    用法：auto-pause-cemu [选项]

      --interval 秒             检查间隔，默认 2 秒（最小 0.2）
      --any-gamepad             任意已连接的蓝牙手柄都可恢复 Cemu
      --once                    只检测并报告一次，不发送信号
      --resume-managed          恢复状态文件中由本程序暂停的 Cemu 后退出
      --verbose                 输出每次检查结果
      -h, --help                显示帮助
    """)
}

private final class Monitor {
    private let detector: BluetoothControllerDetector
    private let finder: CemuProcessFinder
    private let reportOnly: Bool
    private let verbose: Bool
    private let store: ManagedPIDStore
    private var state: PauseState
    private var lastConnected: Bool?
    private var lastPIDs: Set<pid_t> = []

    init(options: Options) {
        store = ManagedPIDStore()
        state = PauseState(managedPIDs: store.load())
        detector = BluetoothControllerDetector(anyGamepad: options.anyGamepad)
        finder = CemuProcessFinder()
        reportOnly = options.mode == .report
        verbose = options.verbose
    }

    func tick() {
        let connected = detector.isConnected()
        let processes = finder.processes()
        let pids = Set(processes.map(\.pid))

        if verbose || connected != lastConnected || pids != lastPIDs {
            let controllerText = connected ? "已连接" : "未连接"
            let processText = pids.isEmpty ? "未运行" : pids.sorted().map(String.init).joined(separator: ",")
            log("手柄\(controllerText)；Cemu PID：\(processText)")
        }
        lastConnected = connected
        lastPIDs = pids

        guard !reportOnly else {
            if !connected, !pids.isEmpty {
                log("仅报告模式：正常运行时将暂停 Cemu")
            }
            return
        }

        state.reconcile(controllerConnected: connected, processes: processes) { [self] action in
            perform(action)
        }
        persistState()
    }

    func shutdown() {
        let pids = Set(finder.processes().map(\.pid))
        state.resumeAll(liveTargetPIDs: pids) { [self] action in
            perform(action)
        }
        persistState()
    }

    private func perform(_ action: ProcessAction) -> Bool {
        let pid: pid_t
        let signal: Int32
        let verb: String
        switch action {
        case let .pause(value):
            pid = value
            signal = SIGSTOP
            verb = "已暂停"
        case let .resume(value):
            pid = value
            signal = SIGCONT
            verb = "已恢复"
        }

        if kill(pid, signal) == 0 {
            log("\(verb) Cemu（PID \(pid)）")
            return true
        }
        log("无法向 Cemu（PID \(pid)）发送信号：\(String(cString: strerror(errno)))")
        return false
    }

    private func persistState() {
        do {
            try store.save(state.managedPIDs)
        } catch {
            log("无法保存暂停状态：\(error.localizedDescription)")
        }
    }
}

private let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

private func log(_ message: String) {
    print("[\(timestampFormatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

do {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    let monitor = Monitor(options: options)

    if options.mode == .resume {
        monitor.shutdown()
        exit(0)
    }

    monitor.tick()

    if options.mode == .report {
        exit(0)
    }

    log("开始监控；按 Ctrl-C 退出（退出前会恢复由本程序暂停的 Cemu）")

    var signalSources: [DispatchSourceSignal] = []
    for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            log("收到退出信号，正在清理")
            monitor.shutdown()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }

    let timer = Timer.scheduledTimer(withTimeInterval: options.interval, repeats: true) { _ in
        monitor.tick()
    }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.run()
} catch {
    fputs("错误：\(error.localizedDescription)\n", stderr)
    fputs("使用 --help 查看帮助。\n", stderr)
    exit(2)
}
