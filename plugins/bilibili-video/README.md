# bilibili-video

把 bilibili 视频获取到本地为 MP4：

- **下载**：yt-dlp 下载在线视频，最高 4K60 / 杜比视界 / FLAC Hi-Res（需 cookies，skill 内含 2026-11 实测的手动导出流程）
- **还原**：合并客户端离线缓存 `video.m4s` + `audio.m4s` 为 MP4（`-codec copy` 无损，支持 `--output` 归集、`--index` 清单）

HDR 本地播放配置属人工操作，不在此 skill 范围（参考个人笔记 `ai/docs/bilibili-download.md`）。

## 安装

```
/plugin marketplace add yj1438/skills
/plugin install bilibili-video@yj-skills
```

> **改名迁移**：本插件由 `bilibili-restore` v1.0.0 更名并合并下载能力而来（v1.1.0）。已装旧名的请先卸载 `bilibili-restore` 再安装新名——marketplace 的名称变化不会自动替换。
