# 音频来源

`hlddz/` 下的背景音乐、音效和人声均来自腾讯《欢乐斗地主》，版权归腾讯所有，这里仅作个人学习使用。
经由以下开源仓库整理获得：

- https://github.com/palemoky/fight-the-landlord （`bgm/`、`voice/`、`sfx/` 中的大部分）
- jarryherr 的 doudizhu-soundboard（`sfx/select`、`double`、`spring`、`error`、`countdown`）

不要把这些文件发布到公开仓库或随商业版本分发。

## 可以公开的素材

- `kenney/`：Kenney《Casino Audio》1.1，CC0（`kenney/License.txt`），取自
  https://opengameart.org/content/54-casino-sound-effects-cards-dice-chips 。
  五子棋落子用 `chip-lay-*`，悔棋收子用 `chips-collide-1`。
- `guofeng/`：五子棋、象棋的胜/负/和音效，由 `tools/jingles.py` 用五声音阶合成的拨弦声，本项目自制。

## 单独提供的背景音乐

`local/` 下是三首古风背景音乐，由项目作者单独提供，不进仓库：

- `lobby.ogg`：大厅
- `gomoku.ogg`：五子棋
- `xiangqi.ogg`：象棋

文件缺失时对应界面不放背景音乐，不影响运行。
