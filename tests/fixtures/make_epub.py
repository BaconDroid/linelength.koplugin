#!/usr/bin/env python3
"""Build a small EPUB with known structure: every normal paragraph ends with a marker word endNN, so the
paragraph-last lines can be identified from the text itself and compared with what the code detects.
Writes <out>.epub and <out>.truth.json (paragraph list in order)."""
import json, random, sys, zipfile

out = sys.argv[1]
align = sys.argv[2] if len(sys.argv) > 2 else "justify"   # justify | left
rng = random.Random(42)
vocab = ("the of and to in a was he she it that with for as his her on had at by from they said but not "
         "were an one all would there their what so up out if about who get which go me when make can like "
         "time no just him know take people into year your good some could them see other than then now look "
         "only come its over think also back after use two how our work first well way even new want because "
         "any these give day most us river harbour lantern window shadow morning quiet distant garden letter "
         "wandered whispered remembered silence travelled across narrow bridge ancient carefully gradually "
         "extraordinary unexpectedly considerably mountain valley evening pocket kitchen stranger afternoon").split()

def sentence(n):
    words = [rng.choice(vocab) for _ in range(n)]
    words[0] = words[0].capitalize()
    return " ".join(words)

blocks = []   # (kind, text)
k = 0
def para(nwords, kind="p"):
    global k
    k += 1
    text = sentence(nwords // 2) + ". " + sentence(nwords - nwords // 2 - 1) + " end%02d." % k
    blocks.append((kind, text))

blocks.append(("h2", "Chapter One"))
for nwords in (95, 60, 140, 18):      # long, medium, very long, short (a line or two)
    para(nwords)
k += 1; blocks.append(("p", '"No," she said, end%02d.' % k))               # one-line paragraph
k += 1; blocks.append(("p", '"Not yet," he replied, end%02d.' % k))        # another
for nwords in (120, 75, 150, 40, 110, 90, 130, 55):
    para(nwords)
blocks.append(("verse", ["The river keeps its own counsel,", "the lantern leans toward the shore,",
                         "and nothing here is hurried,", "and nothing here is more."]))
for nwords in (100, 85, 125, 70, 115):
    para(nwords)

css = "p { margin: 0; text-indent: 1.2em; text-align: %s; } p.verse { text-indent: 0; text-align: left; margin: 0.6em 0; } h2 { text-align: center; margin: 1em 0; }" % align
body = []
for kind, text in blocks:
    if kind == "verse":
        body.append('<p class="verse">' + "<br/>".join(text) + "</p>")
    elif kind == "h2":
        body.append("<h2>%s</h2>" % text)
    else:
        body.append("<p>%s</p>" % text)
xhtml = ('<?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head>'
         '<title>t</title><link rel="stylesheet" type="text/css" href="s.css"/></head><body>' + "\n".join(body) + "</body></html>")
opf = ('<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">'
       '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Line test</dc:title><dc:language>en</dc:language>'
       '<dc:identifier id="id">linetest</dc:identifier></metadata><manifest>'
       '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/><item id="s" href="s.css" media-type="text/css"/>'
       '<item id="n" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="n"><itemref idref="c"/></spine></package>')
ncx = ('<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>t</text></docTitle>'
       '<navMap><navPoint id="a" playOrder="1"><navLabel><text>One</text></navLabel><content src="c.xhtml"/></navPoint></navMap></ncx>')
container = ('<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
             '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
with zipfile.ZipFile(out + ".epub", "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", container)
    z.writestr("OEBPS/content.opf", opf); z.writestr("OEBPS/toc.ncx", ncx)
    z.writestr("OEBPS/c.xhtml", xhtml); z.writestr("OEBPS/s.css", css)
json.dump([{"kind": kind, "text": text} for kind, text in blocks], open(out + ".truth.json", "w"), indent=1)
print("wrote", out + ".epub", "| blocks:", len(blocks), "| align:", align)
