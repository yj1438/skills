---
name: bilibili-restore
description: 还原 bilibili 离线缓存视频。当用户说"还原 bilibili 视频"、"合并 bilibili 缓存"、"处理离线视频"、"bilibili 视频恢复"、"把 bilibili 下载的视频转成 mp4"、"归集 bilibili 视频"、"导出 bilibili 视频" 时使用此 skill。输入一个目录路径即可批量扫描并合并。
---

## 还原 bilibili 离线视频

将 bilibili 客户端下载的离线缓存（`video.m4s` + `audio.m4s`）合并为可播放的 MP4 文件，并按 `[作者]标题.mp4` 命名。

### 目录结构

bilibili 缓存的标准结构如下：

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

### 前置条件

- ffmpeg 必须在 PATH 中
- 需要 Node.js（无第三方依赖）

### 注意

- 脚本使用 `-codec copy` 不重编码，速度很快且无损
- 如果目录结构不符合 bilibili 缓存格式（没有 index.json / video.m4s / audio.m4s），会提示未找到
- 使用 `--output` 时，即使同名也会自动追加序号避免覆盖
