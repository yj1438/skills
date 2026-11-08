---
name: bilibili-video
description: 把 bilibili 视频获取到本地为 MP4。两条路径：①下载——yt-dlp 下载在线视频（4K/杜比视界/Hi-Res 需 cookies），用户说"下载B站视频"、"下载这个BV号"、"yt-dlp 下载"、"4K下载"、"杜比视界下载"时使用；②还原——合并客户端离线缓存 video.m4s + audio.m4s，用户说"还原bilibili缓存"、"合并m4s"、"处理离线视频"、"bilibili视频恢复"、"归集bilibili视频"、"导出bilibili视频"时使用。HDR 本地播放调参是人工操作，不在本 skill 范围。
---

# bilibili-video：B站视频入库

两条路径按用户意图选择，都以 ffmpeg 为基础依赖。HDR 片源本地播放（MPC-HC 的 HDR 渲染配置）属人工操作，本 skill 不处理。

## 路径一：还原离线缓存

将 bilibili 客户端下载的离线缓存（`video.m4s` + `audio.m4s`）合并为可播放的 MP4 文件，并按 `[作者]标题.mp4` 命名。

### 前置

- ffmpeg 全局安装且在 PATH 中（如 `C:\Program Files\ffmpeg\bin`）
- Node.js（脚本零第三方依赖，任意近版本即可）

### 目录结构

bilibili 缓存的标准结构如下（新一代结构中 `entry.json` 位于 `c_<cid>/` 内、流文件在 `<清晰度>/` 子目录，脚本均兼容）：

```
<输入目录>/
  <owner_id>/
    entry.json          ← 视频元信息（title, owner_name, bvid 等）
    <cid>/
      index.json
      video.m4s         ← 视频流
      audio.m4s         ← 音频流
```

### 使用方式

用户提供一个目录路径，运行 skill 自带的脚本：

```bash
# 基础用法：就地合并，输出到缓存同级目录
node <skill-dir>/scripts/restore.js "<输入目录>"

# 归集到指定目录
node <skill-dir>/scripts/restore.js "<输入目录>" --output "<输出目录>"

# 同时生成视频清单
node <skill-dir>/scripts/restore.js "<输入目录>" --output "<输出目录>" --index

# 就地合并 + 生成清单
node <skill-dir>/scripts/restore.js "<输入目录>" --index
```

`<skill-dir>` 是此 skill 所在目录（即 SKILL.md 的同级目录）。

### 参数说明

| 参数 | 说明 |
|------|------|
| `<输入目录>` | bilibili 缓存根目录（必需） |
| `--output, -o <目录>` | 将合并后的 MP4 输出到指定目录（可选） |
| `--index` | 在输出目录生成 `index.json` 视频清单（可选） |

### 脚本行为

1. 递归扫描目录下所有 `**/index.json`
2. 对每个 `index.json` 所在目录，查找同级的 `video.m4s` 和 `audio.m4s`，以及上级的 `entry.json`
3. 从 `entry.json` 提取 `owner_name`、`title`、`bvid`、`desc` 等元信息生成文件名
4. 非法字符会被替换；同名文件会自动追加序号避免覆盖
5. 如果目标文件已存在则跳过；如果存在旧的 `output.mp4` 则改名
6. 用 `ffmpeg -codec copy` 无损合并
7. **`--output` 模式**：合并后的 MP4 直接输出到指定目录，缓存原文件不受影响
8. **`--index`**：生成 `index.json` 清单文件，包含每个视频的文件名、作者、标题、大小、BV 号等

### 生成的 index.json 格式

```json
{
  "generated_at": "2025-01-01T12:00:00.000+08:00",
  "total": 3,
  "source": "D:\\bilibili_cache",
  "videos": [
    {
      "filename": "[作者名]视频标题.mp4",
      "filepath": "D:\\output\\[作者名]视频标题.mp4",
      "size_bytes": 12345678,
      "size_mb": 11.77,
      "source": "D:\\bilibili_cache\\12345\\c_67890\\80",
      "title": "视频标题",
      "owner_name": "作者名",
      "bvid": "BV1xx...",
      "desc": "视频简介"
    }
  ]
}
```

### 注意

- 脚本使用 `-codec copy` 不重编码，速度很快且无损
- **合并产物只含音视频轨**：弹幕（`danmaku.xml/pb`）和封面（`cover.jpg`）不会带入 MP4；删除源缓存前如需保留，要另行导出
- 如果目录结构不符合 bilibili 缓存格式（没有 index.json / video.m4s / audio.m4s），会提示未找到
- 使用 `--output` 时，即使同名也会自动追加序号避免覆盖

## 路径二：下载在线视频（yt-dlp）

### 前置

- yt-dlp 在 PATH 中（升级：`yt-dlp -U`）
- ffmpeg（B 站音视频流分离，下载时自动合并）
- cookies 文件：**登录态决定清晰度上限**。无登录封顶 1080P30（H.264，音轨 AAC ≤186k）；cookie 解锁 1080P60 / 4K60 / 杜比视界 / FLAC Hi-Res（格式 30251）。会员画质还需账号本身具备权限（如大会员）；cookie 有时效，过期后探底档位骤降，重新导出即可
- **cookies「能下载」≠「权益最新」**：旧文件可能是非会员态导出的（2026-11 实测踩过：文件有效但档位被压到 480P）。探底结果远低于账号应有水平时，第一动作是重新导出 cookies，而不是断定画质不存在

### cookies（关键认知）

- **`--cookies-from-browser chrome/edge` 已死**：Chrome 127+ 的 app-bound 加密使必然报 `Failed to decrypt with DPAPI`（yt-dlp #10927，设计使然无解），不要浪费尝试
- 唯一可行：手动导出 Netscape 格式 txt——浏览器登录 bilibili.com → F12 → Network 任选一个 `api.bilibili.com` 请求 → 复制整条 `Cookie:` 头 → 每行 `.bilibili.com TRUE / TRUE <远期过期> name value`（SESSDATA 和 bili_jct 必须在）
- 本机 cookies 惯例路径 `C:\Users\yinjie\Downloads\bili-cookies.txt`
- ⚠️ 凭证文件勿外传勿提交；不用时删除，泄露后在 B 站改密码即失效

### 下载流程

```bash
# 1. 探底：列出所有格式，看分辨率/编码/大小
yt-dlp --cookies <cookies.txt> -F "URL"

# 2. 按格式 ID 下载（最佳视频轨 + 最佳音轨，ffmpeg 自动合并）
yt-dlp --cookies <cookies.txt> -f "<视频ID>+<音频ID>" \
  -o "D:\dir\%(title)s [%(id)s].%(ext)s" --no-playlist "URL"

# 通用懒人版（默认最优；会员档仍需 cookie）
yt-dlp --cookies <cookies.txt> -f "bv*+ba/b" "URL"
```

### 编码与画质选择

| 编码 | 特点 |
|------|------|
| `avc1`（H.264） | 兼容性最好，无登录档即此编码 |
| `hvc1`（HEVC） | 体积小；杜比视界只有 HEVC 轨 |
| `av01`（AV1） | 介于两者；HDR 档位只有 HEVC / AV1 |

B 站杜比视界是 HLG 基底 + RPU 元数据。下载的 HDR 片本地播放发白属播放器配置问题（Chrome 自动色调映射而播放器需手动配），引导用户按个人笔记调整 MPC-HC，不在本 skill 处理。

### 注意

- 4K/HDR 片源体积可达数百 MB，下载前先 `-F` 探底确认
- **多分 P 视频**：基础 URL 会下载全部分 P，文件名自动带 `pNN 标题`；只下某一 P 用 `URL?p=N`。大文件下载可能**静默失败**（无输出即失败），残片形如 `.fXXXXX.mp4` / `.m4a`，删除残片后对失败分 P 单独重跑即可（2026-11 实测：4 分 P 两个失败，均为网络抖动）
- **同分辨率多编码时 `bv*` 自动选 AV1**（压缩效率优先，码率低但观感同级）；要码率最高的 AVC/HEVC 版本需按 `-F` 表显式指定格式 ID
- Chrome 残留后台进程会锁 cookie 库（仅影响 `--cookies-from-browser`，手动导出的 cookies.txt 不受影响）
