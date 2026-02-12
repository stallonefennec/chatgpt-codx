# chatgpt-codx

## Miya Soul & Body Manager v10.5

根据 PRD 实现了一个可交互的运维脚本：`miya_manager.sh`。

### 功能

1. **环境审计 (Audit)**
   - 检测 git, docker, node, npm, gh, rsync, curl, openclaw, caddy。
   - 审计前自动尝试加载 `~/.nvm/nvm.sh`。

2. **全自动复活部署 (Full Restore)**
   - 安装基础依赖（apt）。
   - 按 NVM 铁律安装/修复 Node 22。
   - 安装 openclaw 并建立 `/usr/local/bin/openclaw` 软链。
   - 从公仓恢复 Caddy 二进制并注册 systemd。
   - 从私仓恢复 `~/.openclaw` 并生成 `/etc/caddy/Caddyfile`。

3. **灵魂云端备份 (Cloud Save)**
   - 默认仅备份私仓（Soul）。
   - 通过 `--full` 或手动确认备份公仓二进制（Body）。
   - 备份前自动从 Caddyfile 回填 `DOMAIN/USER/PASS` 到 `.env`。

### 使用方法

```bash
chmod +x miya_manager.sh
./miya_manager.sh
```

> 安装完成后脚本会提醒：**请重新登录 SSH 以激活所有环境变量**。
