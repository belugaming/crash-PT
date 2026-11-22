#!/bin/sh
# 把 test32.ini 转成 OpenClash 覆写模块 openclash/test32.conf
# GitHub Action 在 test32.ini 改动后自动运行；本地也能跑：sh scripts/openclash_module.sh
#
# 模块只有分组、规则集和规则，不含机场名字和任何链接以外的私人信息。
# 机场分组由各自路由器上的本地模块追加进第一个分组（🚀 节点选择）。
cd "$(dirname "$0")/.." || exit 1
INI=${1:-test32.ini}
OUT=${2:-openclash/$(basename "$INI" .ini).conf}
T=${TMPDIR:-/tmp}/oc_module.$$
trap 'rm -f "$T".*' EXIT

sh scripts/ini2yaml.sh "$INI" "$T.yaml" || exit 1

mkdir -p "$(dirname "$OUT")"
{
  echo "# crash-PT $(basename "$INI") 的 OpenClash 覆写模块"
  echo "# 由 GitHub Action 从 $(basename "$INI") 自动生成，别手改；改规则请改 $(basename "$INI")"
  echo "# 在 OpenClash「覆写设置 → 覆写模块」里用网址导入，类型选 http"
  echo "[General]"
  echo "# 定时更新下载到新版本后自动重启 OpenClash"
  echo "RESTART=1"
  echo "[YAML]"
  # 去掉第一行（带转换时间的注释，不然每次都算有改动）和机场分组占位符；
  # 顶层键加 !：整段替换订阅里自带的分组和规则
  sed 1d "$T.yaml" | awk '
    /^[[:space:]]*#/ { next }
    /^[a-z-]+:/ { sub(/:/, "!:") }
    { gsub(/, \{providers_tags\}/, ""); gsub(/\{providers_tags\}, /, ""); gsub(/\{providers_tags\}/, "") }
    { gsub(/path: \.\/ruleset\//, "path: ./rule_provider/") }
    { print }
  '
} > "$T.out"

grep -q "providers_tags" "$T.out" && { echo "✗ 还有没去掉的 {providers_tags}"; exit 1; }
for k in "proxy-groups!:" "rule-providers!:" "rules!:"; do
  grep -q "^$k" "$T.out" || { echo "✗ 生成结果缺少 $k"; exit 1; }
done
mv -f "$T.out" "$OUT"
echo "已写入 $OUT"
