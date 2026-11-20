# Word count: a line-length checker for KOReader

Select one line of text in KOReader and the highlight dialog tells you how many characters it holds
and whether that is a good line length for reading. Tap the button for the details.

```
Line: 58 chars · Excellent
```

## Why this exists

I wanted the lines of a book to land in the recommended range of characters per line, and the way to
get there is to change the font size and the margins until they do. KOReader has no way to show that
number. What I did instead was retype a line into a word counter on my computer or phone, read off
the characters including spaces, go back to the e-reader, change a setting, and start again.

This plugin does the counting where the text is, so the only thing left to do is to play with the font
size and margins until the line reads **Excellent**.

## Using it

1. Open a book. Long-press the first word of a line and drag to the end of the line.
2. The selection dialog has one extra button, last and full width: `Line: 58 chars · Excellent`.
3. Tap it for a card with the character count, the verdict, the counts with and without spaces, the
   word count, and the four ranges with yours marked.
4. Change the font size or the margins, select another line, and check again.

The number is for whatever you select, so select one line. In justified text the lines differ by a few
characters, so check two or three.

## What the ranges are

A "character" is a character of the line including spaces and punctuation. The ranges come from print
typography and from accessibility guidance on the length of a line (the "measure"):

| Characters | Verdict | Basis |
|---|---|---|
| under 45 | Short | Below Bringhurst's 45 to 75 range for a single column |
| 50–66 | Excellent | From the 50–60 that Ruder found optimal (as quoted by Baymard) up to the 66 that Bringhurst calls ideal |
| 45–49 and 67–75 | Comfortable | Inside Bringhurst's 45 to 75 range but off the ideal; 75 is also Baymard's upper limit |
| 76–80 | Still readable | Past 75, within the 80-character limit of WCAG 1.4.8 |
| 81 and more | Too long | Over the 80-character limit of WCAG 1.4.8 |

These are guidelines, not measurements of your reading. Bringhurst words his figures as "widely
regarded", and the sources do not agree to the character. The bands are a way to see at a glance where a
line sits between them.

Not covered:

- **Two columns.** Bringhurst gives 40 to 50 characters as better for multi-column work. The ranges
  above are for a single column, so a good two-column line of 40 to 44 characters shows as "Short".
- **Chinese, Japanese and Korean.** WCAG puts the limit at 40 glyphs for these scripts, not 80.
- **Landscape.** The ranges apply unchanged. A wider page holds more characters per line at the same
  font size, so raise the font size or the margins to stay in range.

## What is counted

- Characters are Unicode characters, so `é` is one, however it is encoded.
- The selection is cleaned the way KOReader's Copy cleans it: the ends are trimmed and runs of spaces
  become one space.
- Invisible characters (soft hyphen, zero-width space and joiners, direction marks, byte order mark)
  are not counted.
- A word is a run of characters between spaces that has at least one character that is not
  punctuation, so a lone dash or `...` is not a word.

## Colour

On a colour screen, with KOReader's colour rendering on, the number, the verdict and the four range rows
are drawn in the Okabe–Ito palette, which is chosen to stay distinguishable with common forms of colour
blindness:

| Verdict | Colour |
|---|---|
| Excellent | `#0072B2` |
| Comfortable | `#009E73` |
| Still readable | `#E69F00` |
| Too long | `#D55E00` |

On a black-and-white screen, with colour rendering off, and for "Short", everything is in the normal
text colour. The button in the dialog is always plain, like the others.

## Install

Copy this folder into KOReader's plugins folder as `wordcount.koplugin` and restart KOReader. On a Kobo
that is `.adds/koreader/plugins/`. The plugin needs `_meta.lua`, `main.lua` and the `wcount/` folder.

It adds its button with `ReaderHighlight:addToHighlightDialog`, so it needs a KOReader that has that. It
was written and tried on a Kobo Libra Colour with KOReader v2026.07.

## How it works

- `main.lua` registers the button in slot `13_line_length`. KOReader sorts the buttons by that key, so
  the button comes after the built-in ones. It builds the label each time the dialog opens.
- `wcount/counter.lua` counts and `wcount/rating.lua` holds the ranges. Neither uses KOReader, so both
  are tested on a desktop.
- `wcount/report.lua` shapes the numbers for the card, and `wcount/details.lua` draws it from KOReader's
  own widgets. If building the card fails, the same information is shown as plain text.
- `wcount/colortext.lua` is a `TextWidget` that keeps the colour. KOReader's `TextWidget` blits glyphs
  through `getColor8A()`, which keeps only the brightness of a colour, so any text colour comes out grey.
  This widget draws the same glyphs with `colorblitFromRGB32` when the colour is not a grey, and
  defers to `TextWidget` otherwise.

## Tests

```
python3 -m venv .venv && .venv/bin/pip install lupa
.venv/bin/python tests/run.py
```

There is no `lua` binary needed: the tests run in [lupa](https://pypi.org/project/lupa/). They cover
the counting (checked against Python's own `len()` on 3000 random strings), every edge of every range,
the card's data, and the wiring in `main.lua` with KOReader stubbed out. The wiring test models source,
not the device.

`tests/render.lua` draws the button dialog and the cards with a desktop build of KOReader and saves
PNGs at the size of a Libra Colour. It shows what the code draws into KOReader's buffer, not what a
screen displays. The header of the file says how to run it.

## License

AGPL-3.0-or-later, the same as KOReader. See [LICENSE](LICENSE).

## Sources

- Robert Bringhurst, *The Elements of Typographic Style*, as quoted in [2.1.2 Choose a comfortable
  measure](http://webtypography.net/2.1.2): "Anything from 45 to 75 characters is widely regarded as a
  satisfactory length of line for a single-column page set in a serifed text face in a text size. The
  66-character line (counting both letters and spaces) is widely regarded as ideal. For multiple column
  work, a better average is 40 to 50 characters."
- Baymard Institute, [Readability: The Optimal Line Length](https://baymard.com/research-articles/line-length-readability):
  "optimal line length for body text is 50–60 characters per line, including spaces" (Emil Ruder), and
  "up to 75 characters is acceptable".
- W3C, [Understanding Success Criterion 1.4.8: Visual Presentation](https://www.w3.org/WAI/WCAG22/Understanding/visual-presentation.html):
  "Width is no more than 80 characters or glyphs (40 if CJK)."
