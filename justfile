# AIDEV-NOTE: Swift 6.4 の Command Line Tools では、テストを書き換えた直後の
# swift test が「plugin for module 'TestingMacros' not found」で不定期に落ちる
# (再実行すると通る)。プラグインの場所を明示すると安定する。
# --build-system native は Testing モジュール自体を見つけられないので使えない。
# TOOLCHAIN_DIR は flake.nix の shellHook が CLT / Xcode のどちらかに合わせて決める
testing_plugins := env("TOOLCHAIN_DIR") / "usr/lib/swift/host/plugins/testing"

default: check

build:
    swift build

test:
    swift test -Xswiftc -plugin-path -Xswiftc {{ testing_plugins }}

run:
    SWIFT_BACKTRACE=interactive=no swift run air-eater

lint:
    swiftlint lint --strict --quiet

fmt:
    treefmt

check:
    treefmt --fail-on-change
    just lint
    just build
    just test

# 実機で Desktop を切り替えて確かめる。Desktop が 2 個以上あり Ctrl+1…9 が有効な Mac で、手元でだけ回す
e2e:
    swift build
    "$(swift build --show-bin-path)/AirEaterE2E" "$(swift build --show-bin-path)/air-eater"
