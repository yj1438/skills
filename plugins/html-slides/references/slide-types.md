# Slide Layout Catalog

Each slide type includes its HTML pattern and when to use it. Mix layouts across the
presentation — consecutive slides should rarely use the same type.

---

## 1. Title Slide

**When:** Opening slide. Sets the tone.

```html
<div class="slide active" id="s1">
  <div class="kicker">CONTEXT LINE · SMALL CAPS</div>
  <h1 class="headline serif">Main Title</h1>
  <p class="subline">
    Subtitle or tagline<br>
    <span class="en">English companion line</span>
  </p>
  <div style="margin-top:48px;width:48px;height:1px;background:var(--accent);opacity:0.5;"></div>
</div>
```

CSS: center-aligned, largest headline (64–72px), generous vertical spacing.

---

## 2. Big Quote

**When:** A single powerful statement that needs the whole slide. Key thesis, provocative claim,
emotional peak.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <div class="accent-line"></div>
  <div class="big-quote">
    「The quote text with <strong>emphasized keywords</strong>
    that anchor the idea.」
  </div>
  <p class="en" style="margin-top:16px;font-size:16px;">
    "English translation of the quote."
  </p>
</div>
```

CSS: quote at 36–42px, light weight (300), accent-colored bold words.

---

## 3. Two-Column Comparison (VS)

**When:** Contrasting two ideas, paradigms, or approaches. Creates visual tension.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <h2 class="headline" style="font-size:42px;">Headline framing the contrast</h2>
  <p class="en">English companion</p>
  <div class="two-col" style="margin-top:40px;">
    <div class="vs-block vs-left">
      <span class="vs-label">LABEL A</span>
      <h3>Side A Title</h3>
      <p>Supporting points for side A.</p>
      <p class="en">English companion</p>
    </div>
    <div class="vs-block vs-right">
      <span class="vs-label">LABEL B</span>
      <h3>Side B Title</h3>
      <p>Supporting points for side B.</p>
      <p class="en">English companion</p>
    </div>
  </div>
</div>
```

CSS: `.vs-left` uses warm/accent color, `.vs-right` uses cool/contrast color. Each side gets
a tinted label badge.

---

## 4. Three-Card Grid

**When:** Presenting three parallel ideas, steps, or pillars. Works well for frameworks.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <h2 class="headline" style="font-size:42px;">Headline</h2>
  <p class="subline">Brief framing text.</p>
  <div class="three-col" style="margin-top:44px;">
    <div class="card">
      <div class="num">01</div>
      <h3>Card Title</h3>
      <p>Card description.</p>
    </div>
    <!-- repeat for 02, 03 -->
  </div>
</div>
```

CSS: cards with subtle background (rgba white on dark, or light shadow on light themes),
border-radius 16–20px, numbered with large light-weight digits.

---

## 5. Headline + Callout Box

**When:** A key point that needs visual emphasis beyond the normal text hierarchy.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <h2 class="headline" style="font-size:40px;">Main Point</h2>
  <p class="subline">Supporting context.</p>
  <div style="margin-top:40px;padding:24px 32px;background:var(--accent-dim);
      border-radius:16px;border-left:3px solid var(--accent);">
    <p style="font-size:16px;font-weight:500;color:var(--white);">
      The key insight — one sentence that matters.
    </p>
    <p class="en">English companion</p>
  </div>
</div>
```

---

## 6. Stats Row

**When:** Showcasing key numbers or metrics. Impact through scale.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <h2 class="headline" style="font-size:40px;">Headline</h2>
  <div class="stat-row">
    <div class="stat-item">
      <div class="stat-num">42</div>
      <div class="stat-label">Label<br><span class="en">English label</span></div>
    </div>
    <!-- repeat for 2–3 more stats -->
  </div>
</div>
```

CSS: stat numbers at 48–56px, weight 200 (hairline), accent color. Labels small and muted.
Stats separated by thin vertical dividers.

---

## 7. Two-Column: Text + Feature Box

**When:** One side explains, the other side highlights a list, checklist, or call-to-action.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <h2 class="headline" style="font-size:40px;">Headline</h2>
  <div class="two-col" style="margin-top:44px;">
    <div>
      <div class="accent-line"></div>
      <p style="font-size:17px;line-height:1.9;color:var(--grey-400);">
        Explanatory text on the left.<br>
        Can span multiple paragraphs.
      </p>
    </div>
    <div>
      <div style="padding:32px;background:var(--accent-dim);border-radius:20px;">
        <p style="font-weight:600;color:var(--accent);margin-bottom:12px;">
          BOX TITLE
        </p>
        <p style="font-size:15px;line-height:2;color:var(--white);">
          ❶ First point<br>
          ❷ Second point<br>
          ❸ Third point
        </p>
      </div>
    </div>
  </div>
</div>
```

---

## 8. Two-Column: Tag Lists (Can / Cannot)

**When:** Showing capabilities vs limitations, dos vs don'ts, or two parallel lists.

```html
<div class="slide" id="sN">
  <div class="kicker">SECTION LABEL</div>
  <h2 class="headline" style="font-size:38px;">Headline</h2>
  <div class="two-col" style="margin-top:44px;">
    <div>
      <span class="tag">POSITIVE LABEL</span>
      <div style="font-size:17px;line-height:2;color:var(--grey-400);">
        ✓ Item one<br>
        ✓ Item two<br>
        ✓ Item three
      </div>
    </div>
    <div>
      <span class="tag" style="border-color:var(--red);color:var(--red);">
        NEGATIVE LABEL
      </span>
      <div style="font-size:17px;line-height:2;color:var(--grey-400);">
        ✗ Item one<br>
        ✗ Item two<br>
        ✗ Item three
      </div>
    </div>
  </div>
</div>
```

---

## 9. Closing Slide

**When:** Final slide. Bookend the opening. Can echo the title or land on a call to action.

```html
<div class="slide" id="sN">
  <div style="width:48px;height:1px;background:var(--accent);margin-bottom:32px;opacity:0.5;"></div>
  <p style="font-size:13px;letter-spacing:3px;text-transform:uppercase;
     color:var(--accent);font-weight:600;margin-bottom:20px;">
    CLOSING LABEL
  </p>
  <h2 class="headline serif" style="font-size:48px;line-height:1.3;">
    Closing statement<br>or call to action
  </h2>
  <p class="en" style="margin-top:16px;font-size:17px;">
    English companion
  </p>
  <p style="margin-top:48px;font-size:14px;color:var(--grey-600);letter-spacing:1px;">
    ATTRIBUTION · CREDIT · YEAR
  </p>
</div>
```

CSS: center-aligned, serif font for gravitas, minimal elements.
