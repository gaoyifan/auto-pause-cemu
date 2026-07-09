# Auto Pause Cemu

[![CI](https://github.com/gaoyifan/auto-pause-cemu/actions/workflows/ci.yml/badge.svg)](https://github.com/gaoyifan/auto-pause-cemu/actions/workflows/ci.yml)

macOS 后台小程序：指定蓝牙手柄断开时向 Cemu 发送 `SIGSTOP`，手柄重新连接时发送 `SIGCONT`。暂停后的 Cemu 不再持续占用 CPU/GPU，从而降低耗电。

默认手柄是 PS5 DualSense（`DualSense Wireless Controller`，Sony `054c:0ce6`），默认 Cemu bundle ID 是 `info.cemu.Cemu`。

## 构建与试运行

```sh
make test
make build

# 只报告一次，不暂停 Cemu
.build/release/auto-pause-cemu --once

# 前台运行；Ctrl-C 退出时会先恢复由本程序暂停的 Cemu
.build/release/auto-pause-cemu
```

如果希望任一蓝牙手柄连接后都恢复 Cemu：

```sh
.build/release/auto-pause-cemu --any-gamepad
```

使用 `--help` 查看检查间隔、任意蓝牙手柄模式及维护命令。

## 登录后自动运行

```sh
make install
```

这会把 release 程序复制到 `~/Library/Application Support/AutoPauseCemu/`，并创建、加载用户 LaunchAgent。日志位于 `~/Library/Logs/AutoPauseCemu/`。

卸载：

```sh
make uninstall
```

## Nix 与 nix-darwin

本仓库导出默认 package 和 nix-darwin module。加入 nix-darwin flake inputs：

```nix
auto-pause-cemu = {
  url = "github:gaoyifan/auto-pause-cemu";
  inputs.nixpkgs.follows = "nixpkgs-darwin";
};
```

导入并启用模块：

```nix
{
  imports = [inputs.auto-pause-cemu.darwinModules.default];
  services.auto-pause-cemu.enable = true;
}
```

也可以直接运行或构建：

```sh
nix run github:gaoyifan/auto-pause-cemu
nix build github:gaoyifan/auto-pause-cemu
```

## 安全行为

- 只把通过蓝牙连接的目标手柄算作“已连接”；USB 线连接不会触发恢复。
- 只恢复本程序亲自暂停且仍然属于 Cemu 的 PID，不会恢复启动前已被其他工具暂停的 Cemu。
- 收到 `SIGINT`、`SIGTERM` 或 `SIGHUP` 时，退出前恢复由本程序暂停的 Cemu。
- 暂停所有权保存在 `~/Library/Application Support/AutoPauseCemu/managed-pids.json`；launchd 强制重启后，新实例仍能安全接管。
- 卸载或手动 bootout 后，可运行 `auto-pause-cemu --resume-managed` 恢复状态文件中由本程序暂停的 Cemu。
- `--once` 始终是只报告模式，防止一次性命令把 Cemu 留在暂停状态。
