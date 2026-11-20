# Line Length: a line-length checker for KOReader

*Formerly called Word count.*

Two ways to check how long the lines of a book are, and whether that is a good length for reading:

- **A line you select.** Select one line of text and the highlight dialog tells you how many characters it
  holds and how that reads. Tap the button for the details.
- **The whole page.** *Line length: this page* in the Typeset menu lists the longest lines on the page you
  are looking at, rated by the longest. No selection, and no highlight dialog needed. The card also has
  steppers for the margins and the text size, and measures the page again after each change, so you
  can adjust until the longest line reads Excellent, then keep it or put everything back with Cancel.

| <img src="docs/selection-dialog.png" width="400" alt="The selection dialog in KOReader with an extra last button reading Line: 56 chars, Excellent"> | <img src="docs/details-card.png" width="400" alt="The details card: 56 characters, Excellent, counts with and without spaces, words, and the four ranges"> |
|:---:|:---:|
| *The selection dialog after selecting a line. The extra button at the bottom shows how many characters the line has (56 here) and where that falls: Excellent.* | *Tap the button for the card: the count with and without spaces, the word count, and the four ranges with yours marked. It is drawn in colour on a colour screen.* |
| <img src="docs/menu-item.png" width="400" alt="KOReader's Typeset menu with the last item, Line length: this page, highlighted"> | <img src="docs/page-card.png" width="400" alt="The page card: 59 characters in the longest line, Excellent, the three longest lines L11, L7 and L12 with 59, 58 and 56 characters, and the four ranges"> |
| *The whole-page mode starts from the Typeset menu: the last item, Line length: this page.* | *The card for the whole page: the longest line has 59 characters (Excellent). Under it are the three longest lines, each with its place on the page (L11 is the eleventh line) and its length, then the four ranges. The X in the corner closes it.* |

Screenshots from a Kobo Libra Colour running KOReader v2026.07.2. The card screenshot is from version 0.7.0, before
the margin and text size controls were added under the four ranges; see
[Changing the margins and the text size from the card](#changing-the-margins-and-the-text-size-from-the-card).

## Requirements

- Any device KOReader runs on. Colour needs a colour screen with KOReader's colour rendering on; on
  a black-and-white screen the card is in black and white. Only a Kobo Libra Colour has been tried.

## Why this exists

I wanted the lines of a book to land in the recommended range of characters per line, and the way to
get there is to change the font size and the margins until they do. KOReader has no way to show that
number. What I did instead was retype a line into a word counter on my computer or phone, read off
the characters including spaces, go back to the e-reader, change a setting, and start again.

This plugin does the counting where the text is, so the only thing left to do is to play with the font
size and margins until the line reads **Excellent**.

## Using it

### A line you select

1. Open a book. Long-press the first word of a line and drag to the end of the line.
2. The selection dialog has one extra button, last and full width: `Line: 58 chars · Excellent`.
3. Tap it for a card with the character count, the verdict, the counts with and without spaces, the
   word count, and the four ranges with yours marked.
4. Change the font size or the margins, select another line, and check again.

The number is for whatever you select, so select one line. In justified text the lines differ by a few
characters, so check two or three.

### The whole page

1. Open the Typeset menu (the tab with a page of text on it) and tap **Line length: this page**.
2. The card shows the **longest line** on the page, its verdict and the four ranges. Under the bold heading
   *Longest lines on this page:* are the three longest lines, each as `L5: start of the text … 54`: `L5` is
   that line's place on the page, counted from the top (the fifth line), then the start of its text, then
   its length in characters.
3. Tap the X in the top right corner to close it. Tapping outside the card closes it too.

#### Changing the margins and the text size from the card

Under the ranges the card has two steppers, **Margins** and **Text size**, each with a **−** and a **+** around
the current value, and two buttons: **Cancel** and **Done**.

- A **+** makes the lines **shorter** (wider margins, bigger text) and a **−** makes them **longer**. If the
  longest line is too long, tap **+** on Margins or on Text size.
- The number between the buttons is the setting as KOReader's own Typeset menu shows it (margins 10, text size
  22), so you can see what you have set and set it again by hand.
- Each tap changes the width of the text by about 5%, which is about 3 characters on a line of 60. Smaller
  steps would not show: lines break at whole words, so the longest line only moves when the width moves by a
  few percent.
- **The card shrinks while you adjust.** A tap on a stepper drops everything but the title, the number, the
  verdict and the controls, so the page behind it shows and you can watch it change. It stays small for as long
  as you like. The bottom edge stays where it was, so the buttons do not move under your
  finger. The two buttons at the bottom change with it:
  - **Accept** keeps what you changed, measures the page again, and shows the full card with the new numbers.
  - **Cancel** puts the margins and the text size back to what they were when you opened the card, and shows the
    full card again. That includes changes you accepted earlier.
- On the full card, **Done** closes it and keeps what you changed; **Cancel** puts everything back to what it was
  when you opened the card, and closes it. The X and a tap outside the card close it and keep what you changed.
- After each tap the book is laid out again, the page is measured again, and the card shows the new numbers.
  The line numbers (`L5`) are those of the new layout.
- KOReader renders only the chapter you are in when you change a setting, and only when it next draws the page
  ("partial rerendering", on by default for books with several chapters). The plugin draws the page first and
  measures it after, so the numbers are for the page as it is now, not for the one before your last tap. A tap can
  take a little longer for that.
- **Margins** are the left and right margins together; the top and bottom margins are not touched. They are
  changed by the same amount on both sides, so margins that differ stay different (the stepper then shows
  both, like `10/14`).
- These are the same settings as in KOReader's Typeset menu, set the same way, so they apply to the book you
  are reading and are saved with it.
- A button that cannot go further is grey. KOReader's own limits apply: each margin from 0 to 140, the text
  size from 12 to 255.
- With the controls on the card, a tap that misses a button does nothing; only the X, **Done**, **Cancel** or a
  tap outside the card closes it. The card of a selected line has no buttons and still closes on any tap.
- Changing the margins or the text size lays the whole book out again, so page numbers change and a long book
  can take a moment. The page you are on keeps its place in the text: after a change it can start a little
  earlier or later, and Cancel brings it back to the same place.
- The number is for one page. Dialogue, indents and headings have different line lengths, so a layout that
  gives this page an Excellent line is a good start, not a guarantee for the whole book.

The action is also in KOReader's gesture list as *Line length: this page*, so it can go on a tap zone, a
corner or a profile.

Why the longest lines and not an average: the last line of every paragraph is short, so an average
over the page would say less about the text than about how many paragraphs it has. The longest lines are
not touched by that, and a line that is too long is the one that tires the eye. It is also the strictest
reading: justified lines vary by a few characters, so the longest is a little above the typical line.
The verdict is the longest line's.

It reads the lines of the page that is on screen, so it works only in books that reflow (EPUB, FB2 and
the like), not in a PDF or a comic.

Thanks to the reddit user [Zanzel_Melancthones](https://www.reddit.com/user/Zanzel_Melancthones) for the suggestion to implement it this way.

## What the ranges are

A "character" is a character of the line including spaces and punctuation. The ranges come from print
typography and from accessibility guidance on the length of a line (the "measure"):

| Characters | Verdict | Basis |
|---|---|---|
| under 50 | Short | Below the 50 where Baymard and Ruder start. Bringhurst accepts lines down to 45 in a single column, so 45–49 shows as Short |
| 50–66 | Excellent | From the 50–60 that Ruder found optimal (as quoted by Baymard) up to the 66 that Bringhurst calls ideal |
| 67–75 | Comfortable | The rest of the satisfactory range: inside Bringhurst's 45 to 75 and Baymard's 50 to 75, but past the ideal |
| 76–80 | Still readable | Past 75, within the 80-character limit of WCAG 1.4.8 |
| 81 and more | Too long | Over the 80-character limit of WCAG 1.4.8 |

These are guidelines, not measurements of your reading. Bringhurst words his figures as "widely
regarded", and the sources do not agree to the character. The bands are a way to see at a glance where a
line sits between them.

Not covered:

- **Two columns.** Bringhurst gives 40 to 50 characters as better for multi-column work. The ranges
  above are for a single column, so a good two-column line of 40 to 49 characters shows as "Short".
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
- **Hyphenated words.** Selecting text snaps to whole words, so if a line ends in a hyphenated word
  (`moun-` / `tain`) the button counts the whole word on that line. The whole-page check does not: it
  asks KOReader where each letter of the first and last word of every line is drawn and counts only
  those on the line. On a test book the plain count made the longest line read up to 10 characters too
  long. The hyphen that KOReader draws at the break is not counted.

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

1. Download `linelength.koplugin.zip` from the [latest release](../../releases/latest) and extract it.
2. Copy the `linelength.koplugin` folder into KOReader's plugins folder and restart KOReader. On a Kobo
   that is `.adds/koreader/plugins/`.
3. Open a book. Select some text and the button is the last one in the dialog, or open the Typeset menu
   and tap **Line length: this page**.

### Upgrading from Word count

This plugin used to be called Word count, in a folder named `wordcount.koplugin` (versions up to 0.6.0).
**Delete that folder before you copy `linelength.koplugin`.** If both stay, both load and the button and
the menu item show up twice. The plugin keeps no settings, so nothing is lost. A gesture you set to
*Line length: this page* keeps working: the action's internal id is still `wordcount_page` on purpose,
because KOReader stores that id in the gesture settings.

## Tested on

A Kobo Libra Colour (firmware 4.45) with KOReader v2026.07.2. The button, the card, the whole-page mode,
the margin and text size controls (with Cancel, Accept and Done) and the colours show on its screen.

## How it works

- `main.lua` registers the button in slot `13_line_length`. KOReader sorts the buttons by that key, so
  the button comes after the built-in ones. It builds the label each time the dialog opens. It also adds
  the Typeset menu item and the gesture action, whose id is still `wordcount_page` (see Upgrading).
- `linelength/pagelines.lua` reads the lines of the page on screen from KOReader's document engine
  (`getTextFromPositions` for the lines, `getScreenPositionFromXPointer` to find which letters of a
  hyphenated word are on which line, `getTextFromXPointers` to read the text that is left) and picks the
  longest. It does not use KOReader itself: the engine is passed in, so it is tested on a desktop with a
  fake one.
- `linelength/counter.lua` counts and `linelength/rating.lua` holds the ranges. Neither uses KOReader, so both
  are tested on a desktop.
- `linelength/report.lua` shapes the numbers for the card, and `linelength/details.lua` draws it from KOReader's
  own widgets (its steppers and buttons are KOReader's `Button`). It shrinks to the controls when a stepper is
  tapped and is full size again when Accept or Cancel is tapped; it never schedules anything. If building the
  card fails, the same information is shown as plain text.
- After a change, `main.lua` measures the page through `measureSettled`: when KOReader says the rendering is delayed
  (`isRerenderingDelayed`) it draws the page with KOReader's own paint, which renders it, and measures again until
  two measurements agree (three draws at most). Without that, the first measurement is of the old layout and the
  card is one change behind. A fully rendered book is measured at once and nothing is drawn.
- `linelength/layout.lua` works out one step of the margins or the text size, in the units KOReader's own
  menus use. It does not use KOReader, so it is tested on a desktop. `main.lua` applies a step the way the
  Typeset menu does: a `ConfigChange` event (which is what stores the value with the book) and then
  `SetPageHorizMargins` or `SetFontSize`, sent to the reader. KOReader lays the book out again before the
  call returns, so the page is measured again at once and the card is redrawn.
- `linelength/colortext.lua` is a `TextWidget` that keeps the colour. KOReader's `TextWidget` blits glyphs
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
the card's data, the page reading against a fake document engine (hyphenated words, page edges, an
engine that fails), and the wiring in `main.lua` with KOReader stubbed out. The wiring test models
source, not the device.

`tests/engine.lua` runs the page reading against KOReader's real text engine (crengine) on the books
made by `tests/fixtures/make_epub.py`: for every page, justified and left-aligned, at three font sizes,
the line lengths must add up exactly to the text of that page, and every line's number (the `L5`) must be
the row the engine itself lists at that place on the page. It needs the desktop build of KOReader;
the header of the file says how to run it.

`tests/plugin.lua` runs the real `main.lua`, the real engine and the real card together: it checks that the
numbers on the card match the page's own lines, that the X is in the top right corner and its action closes
the card, and that the action runs through KOReader's own gesture dispatcher.

`tests/controls.lua` opens a real `ReaderUI` (KOReader's own font, typeset and footer modules) and sends real
taps to the real buttons: the real margins and text size of the book must change, the card must show what the
page now measures (checked against an independent measurement), the values must be stored with the book,
Cancel must give back the margins, the text size, the number of pages and the page top to the
character (also after an Accept), Done must keep the changes, a tap that misses a button must not close the card,
and a tap outside it must. It also checks the shrinking: the card is smaller and shows only the title, the number,
the verdict and the controls, every button is exactly where it was, it is still small after a pause of more than a
second and the card has scheduled nothing, Accept and Cancel bring the full card back, and Cancel and Done close it
when it is full size.

`tests/partial.lua` does the same with a book that KOReader renders partially (several chapters, big enough for a
cache; `tests/fixtures/make_epub_chapters.py` builds one): after every tap the card must show what the page holds
once it has been drawn, and so must the full card after Accept and the card when it is opened again. Before the
page was drawn first, every one of these taps showed the previous tap's numbers.

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
