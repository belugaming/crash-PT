#!/bin/sh
# 把 subconverter 格式的规则配置（.ini）转换成 merge.sh 用的规则模板（.yaml）
# 用法：sh ini2yaml.sh [ini 链接或本地路径] [输出文件]
#   默认 ini ：belugaming/crash-PT 仓库里的 test32.ini
#   默认输出：脚本所在目录的 test32.yaml（在路由器上就是 /overlay/ShellCrash/test32.yaml）
# 可选环境变量：
#   CDN=0             保留 raw.githubusercontent.com 链接（默认换成 jsdelivr 镜像，国内拉取更稳）
#   TAGS_GROUP=分组名  把机场分组占位符 {providers_tags} 放进哪个分组（默认第一个分组）
# 支持的 ini 写法：
#   ruleset=分组,规则链接[,更新间隔秒]      → rule-providers + RULE-SET 规则
#   ruleset=分组,[]GEOIP,CN / []FINAL      → GEOIP,CN,分组 / MATCH,分组（其他 []类型,值 同理）
#   custom_proxy_group=名称`类型`[]分组或DIRECT`正则`测速链接`间隔,超时,容差
#     []xxx 是引用；.* 表示全部节点；其他文字当作节点名正则（include-all + filter）
SRC=${1:-https://raw.githubusercontent.com/belugaming/crash-PT/refs/heads/main/test32.ini}
OUT=${2:-$(cd "$(dirname "$0")" && pwd)/test32.yaml}
W=${TMPDIR:-/tmp}/ini2yaml.$$
trap 'rm -f "$W".*' EXIT

case "$SRC" in
  http://*|https://*) curl -fsSL -m 60 -o "$W.ini" "$SRC" || { echo "✗ 下载失败：$SRC"; exit 1; } ;;
  *) [ -f "$SRC" ] || { echo "✗ 找不到文件：$SRC"; exit 1; }; cp "$SRC" "$W.ini" ;;
esac
tr -d '\r' < "$W.ini" > "$W.in"
grep -q '^custom_proxy_group=' "$W.in" || { echo "✗ 不像 subconverter 规则配置（没有 custom_proxy_group=）：$SRC"; exit 1; }

awk -v cdn="${CDN:-1}" -v tagsgroup="$TAGS_GROUP" -v src="$SRC" -v now="$(date '+%Y-%m-%d %H:%M')" -v warnfile="$W.warn" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function q(s) {  # YAML 流式写法：含特殊字符时加单引号
  if (s ~ SPECIAL || s ~ /^[-?]/) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }
  return s
}
function sq(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }
function warn(s) { print "  ⚠ " s > warnfile; nwarn++ }
function cdnurl(u,   p, n, a, i, owner, repo, br, start, rest) {
  if (cdn != 1 || u !~ /^https?:\/\/raw\.githubusercontent\.com\//) return u
  p = u; sub(/^https?:\/\/raw\.githubusercontent\.com\//, "", p)
  n = split(p, a, "/")
  owner = a[1]; repo = a[2]
  if (a[3] == "refs" && a[4] == "heads") { br = a[5]; start = 6 } else { br = a[3]; start = 4 }
  rest = a[start]; for (i = start + 1; i <= n; i++) rest = rest "/" a[i]
  return "https://testingcf.jsdelivr.net/gh/" owner "/" repo "@" br "/" rest
}
function pname(u,   b, k) {  # 由链接文件名生成规则集名称（只留英文、数字、_、-）
  b = u; sub(/[?#].*$/, "", b); sub(/.*\//, "", b); sub(/\.[A-Za-z0-9]+$/, "", b)
  gsub(/%[0-9A-Fa-f][0-9A-Fa-f]/, "", b); gsub(/[^A-Za-z0-9_-]/, "", b)
  if (b == "") { anon++; b = "ruleset" anon }
  if (tolower(b) in used) { k = 2; while (tolower(b "_" k) in used) k++; b = b "_" k }   # 不分大小写去重，免得缓存文件撞名
  used[tolower(b)] = 1
  return b
}
BEGIN { SPECIAL = "[][,{}:#&*!|>\"%@`\047]"; ng = 0; npv = 0; nr = 0 }
/^[ \t]*([;#]|$)/ || /^\[/ { next }

/^ruleset=/ {
  v = substr($0, 9); c = index(v, ",")
  if (!c) { warn("看不懂的 ruleset：" $0); next }
  g = trim(substr(v, 1, c - 1)); r = trim(substr(v, c + 1))
  rgroup[g] = 1
  if (substr(r, 1, 2) == "[]") {                       # 内联规则
    r = substr(r, 3)
    if (r == "FINAL" || r == "MATCH") { rules[++nr] = "MATCH," g; next }
    n = split(r, a, ",")
    if (n >= 3) { line = a[1] "," a[2] "," g; for (i = 3; i <= n; i++) line = line "," a[i] }
    else line = r "," g
    rules[++nr] = line; next
  }
  iv = 86400
  if (match(r, /,[0-9]+$/)) { iv = substr(r, RSTART + 1); r = substr(r, 1, RSTART - 1) }
  beh = "classical"; fmt = "text"
  if (sub(/^clash-domain:/, "", r)) { beh = "domain"; fmt = "yaml" }
  else if (sub(/^clash-ipcidr:/, "", r)) { beh = "ipcidr"; fmt = "yaml" }
  else if (sub(/^clash-classic(al)?:/, "", r)) { fmt = "yaml" }
  else sub(/^(surge|quanx):/, "", r)
  if (r !~ /^https?:\/\//) { warn("只支持网络链接的规则集，已跳过：" $0); next }
  base = r; sub(/[?#].*$/, "", base)
  if (base ~ /\.ya?ml$/) fmt = "yaml"
  if (base ~ /\.mrs$/) { fmt = "mrs"; if (beh == "classical") beh = (base ~ /[Ii][Pp]/ ? "ipcidr" : "domain") }
  gsub(/ /, "%20", r)
  if (r in byurl) name = byurl[r]
  else {
    name = pname(r); byurl[r] = name
    npv++; pv_name[npv] = name; pv_beh[npv] = beh; pv_fmt[npv] = fmt; pv_url[npv] = cdnurl(r); pv_iv[npv] = iv
  }
  rules[++nr] = "RULE-SET," name "," g
  next
}

/^custom_proxy_group=/ {
  n = split(substr($0, 20), t, "`")
  ng++; G = ng
  gname[G] = trim(t[1]); gtype[G] = trim(t[2]); gnp[G] = 0
  isgroup[gname[G]] = 1
  if (gtype[G] !~ /^(select|url-test|fallback|load-balance|relay)$/) warn("分组「" gname[G] "」的类型「" gtype[G] "」不认识，照原样输出")
  for (i = 3; i <= n; i++) {
    tok = trim(t[i])
    if (tok == "") continue
    if (substr(tok, 1, 2) == "[]") { gp[G, ++gnp[G]] = substr(tok, 3); continue }
    if (gtype[G] != "select" && gtype[G] != "relay" && tok ~ /^https?:\/\//) { gurl[G] = tok; continue }
    if (gurl[G] != "" && tok ~ /^[0-9]*(,[0-9]*)*$/) {
      split(tok, x, ","); ginterval[G] = x[1]; gtol[G] = x[3]; continue   # 超时（第二项）mihomo 用毫秒，这里不转
    }
    gall[G] = 1
    if (tok != ".*") gfilter[G] = (gfilter[G] == "" ? tok : gfilter[G] "|" tok)
  }
  next
}

END {
  # {providers_tags}：插进指定分组（默认第一个）里 DIRECT 的前面，没有 DIRECT 就放最后
  tg = (tagsgroup != "" ? tagsgroup : gname[1]); T = 0
  for (G = 1; G <= ng; G++) if (gname[G] == tg) T = G
  if (!T) { warn("找不到要放机场分组的「" tg "」，没有插入 {providers_tags}") } else {
    pos = gnp[T] + 1
    for (i = 1; i <= gnp[T]; i++) if (gp[T, i] == "DIRECT") { pos = i; break }
    for (i = gnp[T]; i >= pos; i--) gp[T, i + 1] = gp[T, i]
    gp[T, pos] = "{providers_tags}"; gnp[T]++
  }
  # 自检：引用的分组都要存在
  split("DIRECT REJECT REJECT-DROP PASS COMPATIBLE GLOBAL {providers_tags}", b, " "); for (i in b) builtin[b[i]] = 1
  for (G = 1; G <= ng; G++) for (i = 1; i <= gnp[G]; i++) {
    p = gp[G, i]
    if (!(p in isgroup) && !(p in builtin)) warn("分组「" gname[G] "」引用的「" p "」不是分组（如果它是节点名可以忽略）")
  }
  for (g in rgroup) if (!(g in isgroup) && !(g in builtin)) warn("规则指向的分组「" g "」不存在")

  print "#由 ini2yaml.sh 转换：" src "（" now "）"
  print "proxy-groups:"
  for (G = 1; G <= ng; G++) {
    s = "  - {name: " q(gname[G]) ", type: " gtype[G]
    if (gnp[G]) {   # 注意：busybox awk 会把「变量 (」当成函数调用，所以先算好再拼
      s = s ", proxies: ["
      for (i = 1; i <= gnp[G]; i++) {
        sep = ", "; if (i == 1) sep = ""
        item = gp[G, i]; if (item != "{providers_tags}") item = q(item)
        s = s sep item
      }
      s = s "]"
    }
    if (gall[G]) s = s ", include-all: true"
    if (gfilter[G] != "") s = s ", filter: " sq(gfilter[G])
    if (gurl[G] != "") s = s ", url: " sq(gurl[G])
    if (ginterval[G] != "") s = s ", interval: " ginterval[G]
    if (gtol[G] != "") s = s ", tolerance: " gtol[G]
    print s "}"
  }
  if (npv) {
    print "rule-providers:"
    for (i = 1; i <= npv; i++) {
      ext = (pv_fmt[i] == "text" ? "list" : pv_fmt[i])
      print "  " pv_name[i] ":"
      print "    type: http"
      print "    behavior: " pv_beh[i]
      print "    format: " pv_fmt[i]
      print "    path: ./ruleset/" pv_name[i] "." ext
      print "    url: \"" pv_url[i] "\""
      print "    interval: " pv_iv[i]
    }
  }
  print "rules:"
  for (i = 1; i <= nr; i++) print "  - " rules[i]
  printf "%d %d %d\n", ng, npv, nr > "/dev/stderr"
}' "$W.in" > "$W.yaml" 2> "$W.count" || { echo "✗ 转换失败"; cat "$W.count"; exit 1; }

read -r NG NP NR < "$W.count"
[ "$NG" -gt 0 ] && [ "$NR" -gt 0 ] || { echo "✗ 没转出分组或规则，检查 ini 内容"; exit 1; }
echo "✓ 转换完成：$NG 个分组，$NP 个规则集，$NR 条规则"
[ -s "$W.warn" ] && { echo "自检提醒："; cat "$W.warn"; }

if [ -f "$OUT" ] && [ "$(sed 1d "$OUT")" = "$(sed 1d "$W.yaml")" ]; then
  echo "内容和 $OUT 一样，未改动"
  exit 0
fi
cat "$W.yaml" > "$OUT" || exit 1
echo "已写入 $OUT"
case "$OUT" in /overlay/ShellCrash/*) echo "下一步：sh /overlay/ShellCrash/merge.sh  （用新模板合并订阅并重启）" ;; esac
