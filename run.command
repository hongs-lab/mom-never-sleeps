#!/bin/bash
# Finder에서 더블 클릭하면 현재 Mac에 맞게 빌드한 뒤 실행합니다.
set -euo pipefail
cd "$(dirname "$0")"

on_error() {
    local result=$?
    trap - ERR
    echo
    echo "실행을 준비하지 못했어요. 위 오류 내용을 확인해주세요."
    if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다. " reply; fi
    exit "$result"
}
trap on_error ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "이 프로그램은 macOS 12 이상에서 실행해주세요."
    exit 1
fi

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    echo "Mac의 Command Line Tools가 필요해요."
    echo "터미널에서 xcode-select --install 을 실행해 설치한 뒤 다시 열어주세요."
    if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다. " reply; fi
    exit 1
fi

for asset in assets/mom-actions.png assets/holding assets/snacks; do
    if [[ ! -e "$asset" ]]; then
        echo "이미지를 찾을 수 없어요: $asset"
        echo "ZIP 압축을 모두 푼 뒤 폴더 안의 run.command를 실행해주세요."
        exit 1
    fi
done

if [[ ! -x ./mom || main.swift -nt ./mom || run.command -nt ./mom ]]; then
    echo "도트 엄마를 준비하는 중이에요. 처음 실행할 때는 조금 걸릴 수 있어요."
    build_output="./.mom-build-$$"
    trap 'rm -f "$build_output"' EXIT
    /usr/bin/xcrun swiftc -swift-version 5 -O \
        -target "$(uname -m)-apple-macosx12.0" \
        -framework AppKit -framework SwiftUI \
        main.swift -o "$build_output"
    mv "$build_output" ./mom
fi

./mom --selftest
exec ./mom "$@"
