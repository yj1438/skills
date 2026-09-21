# Style Presets

Each preset defines a color palette, typography choices, and surface/card treatment.
All presets share the same base layout system (1280×720 slides, navigation, responsive scaling).

---

## Apple Dark (Default)

Cinematic, high-contrast. Best for keynote-style delivery and dramatic content.

```css
:root {
  --bg: #0a0a0a;
  --surface: #fafafa;
  --text: #fafafa;
  --text-secondary: #86868b;
  --text-tertiary: #6e6e73;
  --accent: #c9a96e;
  --accent-dim: rgba(201,169,110,0.12);
  --negative: #ff3b30;
  --positive: #34c759;
  --info: #007aff;
  --card-bg: rgba(255,255,255,0.04);
  --card-border: rgba(255,255,255,0.06);
  --card-border-hover: rgba(255,255,255,0.15);
  --slide-w: 1280px;
  --slide-h: 720px;
}
```

**Fonts:** Inter (sans), Noto Serif SC or Georgia (serif), Noto Sans SC (CJK)
```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@200;300;400;500;600;700;800;900&family=Noto+Serif+SC:wght@400;600;700;900&family=Noto+Sans+SC:wght@300;400;500;700&display=swap');
```

**Card style:** Glass-like, subtle background with nearly-invisible border, 20px radius.
**Background:** Solid dark. Slides are dark canvases.
**Accent usage:** Gold/amber for emphasis, numbers, kicker labels, progress bar.

---

## Apple Light

Clean, professional. Best for business, academic, or daytime presentation contexts.

```css
:root {
  --bg: #ffffff;
  --surface: #f5f5f7;
  --text: #1d1d1f;
  --text-secondary: #6e6e73;
  --text-tertiary: #86868b;
  --accent: #007aff;
  --accent-dim: rgba(0,122,255,0.08);
  --negative: #ff3b30;
  --positive: #34c759;
  --info: #5856d6;
  --card-bg: #f5f5f7;
  --card-border: rgba(0,0,0,0.06);
  --card-border-hover: rgba(0,0,0,0.12);
  --slide-w: 1280px;
  --slide-h: 720px;
}
```

**Fonts:** Inter, Georgia, Noto Sans SC
```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@200;300;400;500;600;700;800;900&family=Noto+Sans+SC:wght@300;400;500;700&display=swap');
```

**Card style:** Light grey fill, subtle border, 16px radius, clean shadow on hover.
**Background:** Pure white. Navigation bar gets a light blur treatment.
**Accent usage:** Apple Blue for emphasis, links, and interactive elements.

---

## Notion

Document-like, reading-friendly. Best for content-heavy material, reports, or when the
audience will study the slides as a document.

```css
:root {
  --bg: #ffffff;
  --surface: #f7f7f5;
  --text: #37352f;
  --text-secondary: #787774;
  --text-tertiary: #9b9a97;
  --accent: #2383e2;
  --accent-dim: rgba(35,131,226,0.08);
  --negative: #eb5757;
  --positive: #4dab9a;
  --info: #9064c8;
  --card-bg: #f7f7f5;
  --card-border: rgba(0,0,0,0.08);
  --card-border-hover: rgba(0,0,0,0.16);
  --slide-w: 1280px;
  --slide-h: 720px;
}
```

**Fonts:** Source Serif 4 (serif), Inter (sans)
```css
@import url('https://fonts.googleapis.com/css2?family=Source+Serif+4:ital,wght@0,300;0,400;0,600;0,700;1,400&family=Inter:wght@300;400;500;600;700&display=swap');
```

**Card style:** Warm grey fill, 1px border, 12px radius. No hover effect.
**Background:** Slightly warm white. Typography-driven, less visual drama.
**Accent usage:** Blue for headings and interactive elements. Softer, more restrained.

---

## Tech Futurism

Bold, neon accents on dark. Best for developer/tech audiences, product launches, or when
the content calls for visual energy.

```css
:root {
  --bg: #0b0f19;
  --surface: #131a2b;
  --text: #e4e8f1;
  --text-secondary: #7a8599;
  --text-tertiary: #4a5568;
  --accent: #00e5ff;
  --accent-dim: rgba(0,229,255,0.08);
  --negative: #ff4081;
  --positive: #69f0ae;
  --info: #b388ff;
  --card-bg: rgba(19,26,43,0.8);
  --card-border: rgba(0,229,255,0.12);
  --card-border-hover: rgba(0,229,255,0.3);
  --slide-w: 1280px;
  --slide-h: 720px;
}
```

**Fonts:** JetBrains Mono (mono), Space Grotesk (sans)
```css
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;700&family=Space+Grotesk:wght@300;400;500;600;700&display=swap');
```

**Card style:** Semi-transparent dark fill, neon-tinted borders, 16px radius, subtle glow on hover.
**Background:** Very dark navy. Consider a subtle radial gradient for depth.
**Accent usage:** Cyan/neon for all emphasis. Use glow effects (`text-shadow`, `box-shadow`)
sparingly — only on the most important elements.

---

## Adapting Styles for CJK Content

When the primary language is Chinese, Japanese, or Korean:
- Always include the appropriate Noto font: `Noto Sans SC` (simplified Chinese),
  `Noto Sans TC` (traditional Chinese), `Noto Sans JP` (Japanese), `Noto Sans KR` (Korean)
- Set the `lang` attribute on `<html>` accordingly
- For serif needs, use `Noto Serif SC/TC/JP` instead of Georgia
- The `.serif` class should map to the CJK serif font
- Ensure line-height is at least 1.6 for CJK text (CJK characters are taller)

## Custom Colors

Users can describe a color preference instead of picking a preset. In that case, keep the
structural CSS from the nearest preset but swap the color variables. For example:
- "用红色主题" → keep Apple Dark structure, change accent to `#e63946`
- "蓝色科技风" → keep Tech Futurism structure, change accent to `#4488ff`
