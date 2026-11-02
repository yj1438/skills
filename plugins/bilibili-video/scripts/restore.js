const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

function findFiles(dir, name) {
    const results = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            results.push(...findFiles(path.join(dir, entry.name), name));
        } else if (entry.name === name) {
            results.push(path.join(dir, name));
        }
    }
    return results;
}

function parseArgs(argv) {
    const args = { outputDir: null, index: false, inputDir: null };
    const rest = [];
    for (let i = 2; i < argv.length; i++) {
        if (argv[i] === '--output' || argv[i] === '-o') {
            args.outputDir = argv[++i];
        } else if (argv[i] === '--index') {
            args.index = true;
        } else {
            rest.push(argv[i]);
        }
    }
    if (rest.length > 0) args.inputDir = rest[0];
    return args;
}

function getVideoMeta(entryFile) {
    try {
        const entry = JSON.parse(fs.readFileSync(entryFile, 'utf-8'));
        return {
            title: entry.title || '',
            owner_name: entry.owner_name || '',
            bvid: entry.bvid || '',
            avid: entry.avid || '',
            desc: entry.desc || '',
            page_data: entry.page_data || {},
        };
    } catch {
        return null;
    }
}

function sanitize(name) {
    return name.replace(/[/\\:*?"<>|]/g, '');
}

/**
 * 扫描目录下的 bilibili 离线缓存，合并 video.m4s + audio.m4s 为 MP4
 *
 * bilibili 缓存目录结构:
 *   BASE_DIR/
 *     <owner_id>/
 *       entry.json          — 包含 title, owner_name 等元信息
 *       <cid>/
 *         index.json
 *         video.m4s
 *         audio.m4s
 *
 * 用法: node scripts/restore.js <目录路径> [--output <输出目录>] [--index]
 *
 * 选项:
 *   --output, -o <目录>   将合并后的 MP4 复制/输出到指定目录
 *   --index               在输出目录生成 index.json 视频清单
 */
function restore(baseDir, options = {}) {
    const { outputDir, generateIndex } = options;
    const paths = findFiles(baseDir, 'index.json');

    if (paths.length === 0) {
        console.log('未找到 bilibili 缓存 (没有 index.json)');
        return [];
    }

    if (outputDir) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    const results = [];
    const indexEntries = []; // 用于生成清单

    for (const jsonFile of paths) {
        const dir = path.parse(jsonFile).dir;
        const videoFile = path.resolve(dir, 'video.m4s');
        const audioFile = path.resolve(dir, 'audio.m4s');
        const entryFile = path.resolve(dir, '../entry.json');

        if (!fs.existsSync(videoFile)) {
            results.push({ status: 'skip', reason: 'video.m4s 不存在', dir });
            continue;
        }
        if (!fs.existsSync(audioFile)) {
            results.push({ status: 'skip', reason: 'audio.m4s 不存在', dir });
            continue;
        }

        let outputName;
        let meta = null;
        if (fs.existsSync(entryFile)) {
            meta = getVideoMeta(entryFile);
            if (meta && (meta.owner_name || meta.title)) {
                outputName = sanitize(`[${meta.owner_name}]${meta.title}.mp4`);
            }
        }
        if (!outputName) {
            outputName = `output_${path.basename(dir)}.mp4`;
        }

        // 决定最终输出路径
        let output;
        if (outputDir) {
            output = path.resolve(outputDir, outputName);
            // 处理同名冲突：追加序号
            let counter = 1;
            const base = outputName.replace(/\.mp4$/i, '');
            while (fs.existsSync(output)) {
                output = path.resolve(outputDir, `${base}_${counter}.mp4`);
                counter++;
            }
        } else {
            output = path.resolve(dir, outputName);

            // 如果已经存在同名的最终文件，跳过
            if (fs.existsSync(output)) {
                if (generateIndex) {
                    indexEntries.push(buildIndexEntry(output, meta, dir));
                }
                results.push({ status: 'skip', reason: '已存在', file: output });
                continue;
            }

            // 如果存在旧的 output.mp4，先改名
            const oldOutput = path.resolve(dir, 'output.mp4');
            if (fs.existsSync(oldOutput)) {
                fs.renameSync(oldOutput, output);
                if (generateIndex) {
                    indexEntries.push(buildIndexEntry(output, meta, dir));
                }
                results.push({ status: 'rename', file: output });
                continue;
            }
        }

        // 用 ffmpeg 合并
        const cmd = `ffmpeg -i "${videoFile}" -i "${audioFile}" -codec copy -y "${output}"`;
        console.log(cmd);
        try {
            execSync(cmd, { stdio: 'pipe' });
            if (generateIndex) {
                indexEntries.push(buildIndexEntry(output, meta, dir));
            }
            results.push({ status: 'done', file: output });
        } catch (e) {
            results.push({ status: 'error', reason: e.message, dir });
        }
    }

    // 生成视频清单
    if (generateIndex && indexEntries.length > 0) {
        const indexPath = path.resolve(outputDir || baseDir, 'index.json');
        const indexData = {
            generated_at: new Date().toISOString().replace('Z', '+08:00'),
            total: indexEntries.length,
            source: path.resolve(baseDir),
            videos: indexEntries,
        };
        fs.writeFileSync(indexPath, JSON.stringify(indexData, null, 2), 'utf-8');
        console.log(`\n[清单] 已生成: ${indexPath}`);
    }

    return results;
}

function buildIndexEntry(filePath, meta, sourceDir) {
    const stat = fs.statSync(filePath);
    const entry = {
        filename: path.basename(filePath),
        filepath: filePath,
        size_bytes: stat.size,
        size_mb: Math.round(stat.size / 1024 / 1024 * 100) / 100,
        source: sourceDir,
    };
    if (meta) {
        entry.title = meta.title;
        entry.owner_name = meta.owner_name;
        entry.bvid = meta.bvid || undefined;
        entry.avid = meta.avid || undefined;
        entry.desc = meta.desc || undefined;
        if (meta.page_data && meta.page_data.part) {
            entry.page_title = meta.page_data.part;
        }
    }
    return entry;
}

// CLI 入口
if (require.main === module) {
    const args = parseArgs(process.argv);
    if (!args.inputDir) {
        console.log('用法: node restore.js <目录路径> [--output <输出目录>] [--index]');
        console.log('');
        console.log('选项:');
        console.log('  --output, -o <目录>   将合并后的 MP4 输出到指定目录');
        console.log('  --index               在输出目录生成 index.json 视频清单');
        process.exit(1);
    }
    const absPath = path.resolve(args.inputDir);
    if (!fs.existsSync(absPath)) {
        console.log(`目录不存在: ${absPath}`);
        process.exit(1);
    }

    const outputDir = args.outputDir ? path.resolve(args.outputDir) : null;
    console.log(`扫描目录: ${absPath}`);
    if (outputDir) console.log(`输出目录: ${outputDir}`);
    if (args.index) console.log('将生成视频清单');
    console.log('');

    const results = restore(absPath, { outputDir, generateIndex: args.index });

    console.log('\n--- 结果 ---');
    let done = 0, skipped = 0, errors = 0, renamed = 0;
    for (const r of results) {
        if (r.status === 'done') { done++; console.log(`[完成] ${r.file}`); }
        else if (r.status === 'rename') { renamed++; console.log(`[改名] ${r.file}`); }
        else if (r.status === 'skip') { skipped++; console.log(`[跳过] ${r.dir || r.file}: ${r.reason}`); }
        else if (r.status === 'error') { errors++; console.log(`[错误] ${r.dir}: ${r.reason}`); }
    }
    console.log(`\n合计: ${results.length} 个 | 完成: ${done} | 改名: ${renamed} | 跳过: ${skipped} | 错误: ${errors}`);
}

module.exports = { restore };
