# DouZero 斗地主

人类玩家 + 两个 DouZero AI 的离线斗地主。规则和 AI 都在 **C++ 算法核心**（`core/`，以 GDExtension 形式加载）里，
Godot（`game/`）只负责界面和交互。

```text
core/              算法核心（C++）：规则 + 特征编码 + ONNX 推理 + 对局流程
  src/rules.*      牌型判断 / 合法出牌生成（DouZero move_detector/generator/selector 的移植）
  src/game.*       出牌阶段状态 + 模型输入编码（DouZero GameEnv / get_obs 的移植）
  src/policy.*     ONNX Runtime 推理：每个合法动作打分，取最大值
  src/session.*    一局游戏：发牌、叫地主、出牌、胜负；UI 牌 id（0..53，带花色）<-> 点数
  src/core.*       唯一入口：JSON 请求 -> JSON 回复
  gdextension/     Godot 扩展 DouZeroCore（编译到 game/bin/）
  cli/             douzero-cli：stdin/stdout JSON-lines，用于测试和对照
  fetch_deps.sh    下载 ONNX Runtime（linux-x64 / android-arm64）和 godot-cpp
game/              Godot 4.7 项目（只做 UI）
  models/          三个 DouZero WP 出牌模型（landlord / landlord_up / landlord_down）+ 叫地主模型 bid.onnx
  bin/             编译出的扩展 + libonnxruntime（android/ 下是手机版；编译生成，不进 git）
  douzero.gdextension
  scripts/core_client.gd   调用 DouZeroCore（在工作线程里跑，不卡帧）
  scripts/main.gd          牌桌界面
  scripts/card_view.gd     单张牌（显示顺序：大的在左）
  scripts/hand_view.gd     手牌排列与选牌
  scripts/autotest.gd      自动打一局并截图的冒烟测试
reference/         原 Python 核心，作为 C++ 核心的参照（DouZero 原版 env，Apache-2.0）
  scripts/check_cpp.py     逐步对比两边的叫地主、合法动作、模型打分、事件和局面
  scripts/export_bid_model.py  下载叫地主模型权重并转成 game/models/bid.onnx
```

## 编译和运行

需要 g++、cmake、ninja（本机用 `uv tool install cmake ninja` 装在 ~/.local/bin）。

```bash
cd core
./fetch_deps.sh                                   # 第一次需要（third_party/ 不进 git）
cmake -S . -B build -G Ninja && ninja -C build    # 生成 game/bin/libdouzero.linux.*.so 和 build/douzero-cli
cd .. && godot --headless --path game --import    # 第一次需要：让 Godot 登记扩展
godot --path game                                 # 或者在程序坞打开 Godot，导入 game/project.godot
```

Android arm64：

```bash
cd core
cmake -S . -B build-android -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_HOME/ndk/29.0.14206865/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24
ninja -C build-android douzero_gdext              # 输出到 game/bin/android/
```

导出 APK 还需要：安装 Godot Android 导出模板；导出预设里把 `models/*.onnx` 加进"非资源文件"过滤器。

## 架构：核心 / UI 分离

Godot 只发命令、只按返回的 state 渲染，不包含任何规则判断。`Core.request(cmd, args)`：

| 命令 | 参数 | 作用 |
|---|---|---|
| `new_game` | `seed?` | 洗牌发牌，进入叫地主 |
| `state` | | 取当前状态 |
| `step` | | 让当前 AI 座位走一步（叫地主或出牌），UI 每步之间做动画 |
| `bid` | `call: bool` | 玩家叫地主 / 抢地主（true）或不叫 / 不抢（false），看 `state.bid_stage` |
| `play` | `cards: [id]` | 玩家出牌，不合法返回 `ok:false` + 中文原因 |
| `pass` | | 玩家不出 |
| `hint` | | 用模型给玩家推荐出牌 |

每个回复：`{"ok", "error"?, "event"?, "state", "hint"?}`，state 字段见 `core/src/session.cpp` 的 `Session::state()`。
另有 `debug_setup / debug_eval / debug_play` 三个测试命令，供对照脚本使用。

座位：0 = 我（下方），1 = 下家（右），2 = 上家（左），按 0→1→2 轮流出牌。

### 叫地主（欢乐斗地主 叫/抢）

随机一家先开始，依次选择叫地主或不叫。有人叫了之后，排在他后面、还没表态的人可以抢地主。
如果有人抢，最先叫的人还有最后一次抢回来的机会。最后叫或抢的人当地主，每抢一次倍数 ×2。
三家都不叫就重新发牌。总倍数 = 2^(抢地主次数 + 炸弹数)。

AI 用叫地主模型给 17 张手牌打分，分数 > 0.2 叫，> 0.4 抢（模型作者的阈值）。
用我们的出牌模型实测（1500 局）：分数 < −1 的手牌当地主只赢 8%，0.2~0.4 赢 54%，> 1 赢 86%，
所以这个分数和我们的出牌模型是匹配的。

模型通过 Godot 的 FileAccess 读成字节再交给 ONNX Runtime，所以导出后打包在 .pck/.apk 里也能用。

## 验证

```bash
cd reference && uv sync
uv run pytest -q                              # Python 参照测试 + C++ 核心对照（需先编译 core/build）
uv run python scripts/check_cpp.py 300        # 300 局逐步对照：合法动作、模型打分、局面完全一致
uv run python scripts/validate_models.py 300  # 模型对战随机：地主 ~99%，农民 ~99%
godot --path game -- --autotest               # 通过真实 UI 打一局并截图到 user://autotest/
```

## 模型来源

DouZero WP（Winning Percentage）预训练模型：<https://huggingface.co/palemoky/douzero-baselines>。
叫地主模型：Vincentzyx/DouZero_For_HLDDZ_FullAuto 的 `bid_weights.pkl`（BidModel.Net2，Apache-2.0），
用 DouZero 自对弈数据监督训练；`reference/scripts/export_bid_model.py` 负责下载和转换。
DouZero 官方没有公开叫地主模型（官网演示的叫地主走的是私有服务器接口）。
规则与编码代码来自 <https://github.com/kwai/DouZero>（Apache-2.0）。
