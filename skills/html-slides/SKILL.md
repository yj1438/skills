---
name: html-slides
description: >
  Generate polished HTML presentation slides from any content source (URLs, files, pasted text).
  Reads and restructures source material into a compelling narrative arc, then renders as a
  single-file HTML presentation with keyboard/touch navigation and responsive scaling.
  Supports multiple visual presets (Apple Dark, Apple Light, Notion, Tech Futurism) and
  configurable language (monolingual or bilingual). Use this skill whenever the user wants to:
  create slides, make a presentation, turn an article/document/text into slides, build a deck,
  generate HTML slides, or mentions anything about PPT/Keynote/presentation from content.
  Also trigger when the user shares a URL and asks to "visualize", "present", or "summarize as slides".
---

# HTML Slides — Content-to-Presentation Skill

You are a presentation architect. Your job is to take raw content and transform it into a
compelling, visually polished HTML presentation — a single `.html` file that runs in any browser.

## What You Produce

A single, self-contained HTML file with:
- Fixed 16:9 slide canvas (1280×720) with responsive scaling
- Keyboard navigation (arrow keys, space), touch swipe, dot indicators
- Progress bar, slide counter
- Clean typography, intentional whitespace, high-contrast hierarchy
- No external dependencies beyond Google Fonts CDN

## Phase 1 — Content Extraction

Determine the content source and read it:

| Source Type | How to Read |
|---|---|
| URL | Use `mcp__web_reader__webReader` to fetch and extract text |
| Local file | Use the `Read` tool on the file path |
| Pasted text | Use the text provided directly in the conversation |

Read the full content before proceeding. You need the whole picture to build a good narrative.

## Phase 2 — 结构提纯 (guizang-ppt-skill)

Extract a compelling narrative from the raw content. Do NOT just summarize section by section.
The guizang-ppt-skill logic focuses on **distilling contradictions** rather than outlining sections.

1. **Find the tension.** What is the core conflict, question, or paradigm shift in this material?
   Good presentations revolve around a central tension — not a table of contents. Look for
   opposing forces (e.g., technology vs humanity, efficiency vs dignity, centralization vs autonomy).

2. **Build the arc.** Structure slides along one of these proven patterns (or adapt as needed):
   - **Challenge → Insight → Action**: Open with the problem, reveal the key insight, close with what to do
   - **Status quo → Disruption → New equilibrium**: Show the old world, the change agent, the new reality
   - **Myth → Reality → Synthesis**: Present a common belief, dismantle it, offer a deeper truth

3. **Assign layouts.** For each slide, pick from the layout catalog in `references/slide-types.md`.
   Every slide should have a clear purpose — if you can't articulate what this slide is *for*, cut it.

4. **Default to ≤12 slides** unless the user specifies otherwise. You can set the max via the
   `--max-slides N` parameter or infer from content volume.

Read `references/slide-types.md` for the full layout catalog with HTML patterns.

## Phase 3 — 文本拟人化降维 (Humanizer-zh)

Transform the extracted content into presentation-ready copy. This is where most AI-generated
slides fail — the text reads like a Wikipedia summary.

The Humanizer-zh logic focuses on **dehydrating** academic/formal language into punchy,
stage-ready delivery copy. It strips away the three hallmarks of AI-generated text:
mechanical tone, preachy authority, and bloated compound sentences.

**Do:**
- Write in short, punchy phrases suitable for live delivery
- Use concrete details over abstractions
- Create emotional rhythm — some slides should feel urgent, others reflective
- Let the visual do heavy lifting; a single powerful sentence beats a paragraph
- Ensure expert texture: precise, sharp, and infectious — not academic dryness,
  but not casual sloppiness either

**Don't:**
- Write in complete paragraphs — slides are not documents
- Use hedging language ("it could be argued that", "one might consider")
- Repeat the same structure across consecutive slides
- Add filler text to fill space — whitespace is a feature
- Use preachy, lecturing tone ("we must remember", "it is important to note")

**Language configuration:**
- Default: match the source language
- If user requests bilingual (e.g., `--lang zh-en`), keep primary language prominent with secondary
  language as a subtle companion line (smaller, lighter color)
- If user specifies a single language, work in that language only

## Phase 4 — 视觉与代码渲染 (frontend-slides)

The frontend-slides aesthetic standard produces single-file HTML presentations with an
Apple-inspired minimalist design philosophy: expansive whitespace, high-contrast element
hierarchy, and intentional typography.

### Choosing a Style Preset

Read `references/styles.md` for the full catalog. Pick based on:
- **Apple Dark**: Default. High contrast, cinematic. Best for keynote-style delivery.
- **Apple Light**: Clean, professional. Best for business/academic contexts.
- **Notion**: Document-like, reading-friendly. Best for content-heavy material.
- **Tech Futurism**: Bold, neon accents. Best for developer/tech audience.

If the user doesn't specify a style, use Apple Dark as the default. Users can specify via
`--style apple-dark|apple-light|notion|tech` or by describing their preference.

### Using the Base Template

Read `references/base-template.html` to get the HTML skeleton with:
- Navigation system (keyboard, touch, dots, counter)
- Responsive scaling logic
- Base slide positioning and transitions
- Progress bar

You MUST use this as your starting point — do not reinvent the navigation or scaling code.
Customize it by applying your chosen style preset's CSS variables and typography.

### HTML Generation Rules

1. **Single file.** Everything in one `.html` — CSS in `<style>`, JS in `<script>`, no externals
   except Google Fonts.
2. **16:9 canvas.** Slide area is exactly 1280×720px. The template handles responsive scaling.
3. **Font loading.** Use the Google Fonts `@import` that matches your style preset. Keep it to
   2–3 font families max (one serif, one sans, one mono if needed).
4. **CSS variables.** Define all colors and key dimensions as CSS custom properties in `:root`
   so the user can tweak the palette later.
5. **Slide IDs.** Number slides sequentially: `id="s1"`, `id="s2"`, etc. Mark the first slide
   with `class="slide active"`.
6. **No inline JS frameworks.** Pure vanilla JS only — no React, no jQuery, no dependencies.
7. **Save the file.** Write the output to the path the user specifies, or to a sensible default
   like `_temp/presentation.html`.

## Quick Reference: User Parameters

| Parameter | Default | Values |
|---|---|---|
| `--max-slides` | 12 | Any positive integer |
| `--style` | apple-dark | apple-dark, apple-light, notion, tech |
| `--lang` | auto | auto, zh, en, zh-en, en-zh, ja, etc. |
| `--output` | `_temp/presentation.html` | Any file path |

These are not formal CLI args — just patterns the user might use in their request. Parse them
from natural language. "Make 8 slides" → `--max-slides 8`. "Notion style" → `--style notion`.

## Examples

**Example 1 — URL input, bilingual:**
Input: "把这个 URL 变成幻灯片：https://example.com/article --lang zh-en --max-slides 10"
→ Fetch URL content, restructure into 10 slides, Chinese primary with English companion lines,
  Apple Dark style, save to `_temp/presentation.html`.

**Example 2 — Pasted text, English only:**
Input: "Turn this into a 6-slide deck: [pasted article about climate policy]"
→ Extract from pasted text, 6 slides, English only, Apple Dark, save to `_temp/presentation.html`.

**Example 3 — Local file, specific style:**
Input: "把这个 PDF 的内容做成 Notion 风格的演示文稿" + file attachment
→ Read the file content, restructure, Notion style, default ≤12 slides, Chinese,
  save to `_temp/presentation.html`.
