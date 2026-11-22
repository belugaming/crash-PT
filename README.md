# crash-PT

PT 站、AI、游戏等分流规则（`*.list`）和 subconverter 规则配置（`test32.ini`）。

## OpenClash

`openclash/test32.conf` 是 OpenClash 能直接导入的覆写模块，由 GitHub Action 在 `test32.ini` 改动后自动生成（`scripts/openclash_module.sh`），**不要手改**。

- 导入：OpenClash →「覆写设置」→「覆写模块」→ 添加，类型 http，网址
  `https://raw.githubusercontent.com/belugaming/crash-PT/main/openclash/test32.conf`
- 模块只含分组、规则集和规则，不含机场名字和订阅链接。机场分组由路由器上的本地模块追加进第一个分组（🚀 节点选择）。
- 改规则：只改 `test32.ini`，推送后几十秒 Action 就会更新 `openclash/test32.conf`。

本地转换：`sh scripts/openclash_module.sh`（需要 sh + awk，macOS / Linux / OpenWrt 都能跑）。
