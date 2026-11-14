const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

/**
 * 库清单同步：扫描视频库目录，把未登记的 MP4 增量登记进 video_list.json
 *
 * 覆盖两条来源（按文件名启发式区分）：
 *   - yt-dlp 下载：文件名含 [BVxxx] 或 [BVxxx_pN] 标记 → source: yt-dlp
 *   - 合并/导入（restore.js 产物等）：无 BV 标记 → source: restore_or_import
 *
 * 幂等：已登记文件（含 legacy 历史记录按文件名比对）不会重复登记。
 *
 * 用法: node update-list.js <库目录> [--list <video_list.json 路径>]
 * 依赖: ffprobe 在 PATH 中（探测编码/分辨率/时长；缺失时这些字段为 null，不影响登记）
 */
function parseArgs(argv) {
  const rest = [];
  let listPath = null;
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--list') listPath = argv[++i];
    else rest.push(argv[i]);
  }
  return { libDir: rest[0], listPath };
}

function probeMedia(file) {
  const empty = { video_codec: null, resolution: null, audio_codec: null, duration_sec: null };
  try {
    const out = execSync(
      `ffprobe -v error -show_entries stream=codec_name,codec_type,width,height -show_entries format=duration -of json "${file}"`,
      { stdio: 'pipe' }
    ).toString();
    const media = JSON.parse(out);
    const v = (media.streams || []).find((s) => s.codec_type === 'video') || {};
    const a = (media.streams || []).find((s) => s.codec_type === 'audio') || {};
    return {
      video_codec: v.codec_name || null,
      resolution: v.width ? `${v.width}x${v.height}` : null,
      audio_codec: a.codec_name || null,
      duration_sec: media.format && media.format.duration ? Math.round(parseFloat(media.format.duration) * 10) / 10 : null,
    };
  } catch {
    return empty;
  }
}

// 从文件名提取 BV 号 / 分 P / 纯标题
function parseFilename(fn) {
  const m = fn.match(/\[(BV[0-9A-Za-z]+)(?:_(p\d+))?\]\.mp4$/);
  return {
    source: m ? 'yt-dlp' : 'restore_or_import',
    bvid: m ? m[1] : null,
    part: m && m[2] ? m[2] : null,
    title: fn.replace(/\s*\[BV[0-9A-Za-z]+(_p\d+)?\]\.mp4$/, '').trim(),
  };
}

function main() {
  const { libDir, listPath: listArg } = parseArgs(process.argv);
  if (!libDir) {
    console.log('用法: node update-list.js <库目录> [--list <video_list.json 路径>]');
    process.exit(1);
  }
  const absLib = path.resolve(libDir);
  if (!fs.existsSync(absLib)) {
    console.log(`目录不存在: ${absLib}`);
    process.exit(1);
  }
  const listPath = listArg ? path.resolve(listArg) : path.join(absLib, 'video_list.json');

  // 读取现有清单（不存在则新建）
  let j;
  if (fs.existsSync(listPath)) {
    j = JSON.parse(fs.readFileSync(listPath, 'utf-8'));
  } else {
    j = {
      generated_at: new Date().toISOString(),
      description: 'bilibili 视频库总表',
      total: 0,
      current_count: 0,
      videos: [],
    };
  }

  // 已登记文件名集合：legacy 条目按 recorded_path 的 basename 比对，其余按 filename
  const covered = new Set();
  for (const v of j.videos || []) {
    covered.add(v.legacy ? path.basename(v.recorded_path || '') : v.filename);
  }

  const files = fs.readdirSync(absLib).filter((f) => f.toLowerCase().endsWith('.mp4')).sort();
  const now = new Date().toISOString();
  const added = [];
  for (const fn of files) {
    if (covered.has(fn)) continue;
    const fp = path.join(absLib, fn);
    const stat = fs.statSync(fp);
    const meta = parseFilename(fn);
    const media = probeMedia(fp);
    added.push({
      filename: fn,
      filepath: fp,
      size_bytes: stat.size,
      size_mb: Math.round((stat.size / 1048576) * 100) / 100,
      title: meta.title,
      bvid: meta.bvid,
      part: meta.part,
      ...media,
      source: meta.source,
      status: 'tracked',
      tracked_at: now,
    });
  }

  if (added.length === 0) {
    console.log(`扫描 ${absLib}: ${files.length} 个 mp4，全部已登记，无新增`);
  } else {
    j.videos = added.concat(j.videos || []);
    for (const a of added) {
      console.log(`  + [${a.source}] ${a.filename} | ${a.resolution || '?'} ${a.video_codec || '?'} ${a.size_mb}MB`);
    }
    console.log(`新增登记: ${added.length} 条`);
  }

  j.current_count = (j.videos || []).filter((v) => !v.legacy).length;
  j.total = (j.videos || []).length;
  j.updated_at = now;
  fs.writeFileSync(listPath, JSON.stringify(j, null, 2), 'utf-8');
  console.log(`已写回: ${listPath} | 总计 ${j.total} 条 | 当前在库 ${j.current_count} | 历史 ${j.total - j.current_count}`);

  // 完整性校验：非 legacy 条目的文件必须真实存在
  const missing = (j.videos || []).filter((v) => !v.legacy && !fs.existsSync(v.filepath));
  console.log('非 legacy 完整性:', missing.length === 0 ? '全部存在' : `缺失 ${missing.length} 条!`);
  for (const m of missing) console.log(`  缺失: ${m.filename}`);
}

main();
