#!/usr/bin/env bash
#
# 将 lib/ 下的模块打包成单文件，方便在 VPS 上直接 curl | bash 部署
#
# Usage:
#   ./build.sh
#   # 生成 dist/install.sh

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="${ROOT_DIR}/dist/install.sh"

MODULES=(common os xray network config service report)

mkdir -p "${ROOT_DIR}/dist"

{
    # 入口脚本中模块加载区域之前的部分
    awk '/^# BEGIN_MODULES$/{exit} {print}' "${ROOT_DIR}/install.sh"

    for module in "${MODULES[@]}"; do
        printf '\n# ==================== lib/%s.sh ====================\n\n' "$module"
        # 去掉模块自身的 shebang
        awk 'NR == 1 && /^#!/{next} {print}' "${ROOT_DIR}/lib/${module}.sh"
        printf '\n'
    done

    # 入口脚本中模块加载区域之后的部分
    awk 'found{print} /^# END_MODULES$/{found=1}' "${ROOT_DIR}/install.sh"
} > "${OUT_FILE}"

chmod +x "${OUT_FILE}"

bash -n "${OUT_FILE}" || { rm -f "${OUT_FILE}"; exit 1; }

echo "已生成: ${OUT_FILE}"
