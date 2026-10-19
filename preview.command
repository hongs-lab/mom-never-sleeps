#!/bin/bash
# 브라우저를 조작하지 않고 동작과 간식 8종을 순서대로 보여줍니다.
set -euo pipefail
cd "$(dirname "$0")"
exec /bin/bash ./run.command --demo
