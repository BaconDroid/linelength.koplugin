#!/usr/bin/env python3
"""Build an EPUB with several chapters (several spine items, so KOReader's crengine sees several fragments and can do
partial rerendering of just the chapter on screen). Same kind of text as make_epub.py: justified paragraphs of varied length.
Usage: make_epub_chapters.py <out-without-extension> [chapters] [paragraphs-per-chapter]"""
import random, sys, zipfile

out = sys.argv[1]
chapters = int(sys.argv[2]) if len(sys.argv) > 2 else 5
per_chapter = int(sys.argv[3]) if len(sys.argv) > 3 else 22
rng = random.Random(7)
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

def para(n):
    return "<p>%s. %s.</p>" % (sentence(n // 2), sentence(n - n // 2 - 1))

css = "p { margin: 0; text-indent: 1.2em; text-align: justify; } h2 { text-align: center; margin: 1em 0; }"
lengths = (95, 60, 140, 18, 120, 75, 150, 40, 110, 90, 130, 55, 100, 85, 125, 70, 115)
files = []
for c in range(1, chapters + 1):
    body = ["<h2>Chapter %d</h2>" % c]
    for i in range(per_chapter):
        body.append(para(lengths[(i + c) % len(lengths)]))
    files.append(('<?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head>'
                  '<title>Chapter %d</title><link rel="stylesheet" type="text/css" href="s.css"/></head><body>' % c
                  + "\n".join(body) + "</body></html>"))
manifest = "".join('<item id="c%d" href="c%d.xhtml" media-type="application/xhtml+xml"/>' % (i, i) for i in range(1, chapters + 1))
spine = "".join('<itemref idref="c%d"/>' % i for i in range(1, chapters + 1))
opf = ('<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">'
       '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Chapters test</dc:title><dc:language>en</dc:language>'
       '<dc:identifier id="id">chapterstest</dc:identifier></metadata><manifest>' + manifest +
       '<item id="s" href="s.css" media-type="text/css"/><item id="n" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>'
       '<spine toc="n">' + spine + '</spine></package>')
nav = "".join('<navPoint id="n%d" playOrder="%d"><navLabel><text>Chapter %d</text></navLabel><content src="c%d.xhtml"/></navPoint>' % (i, i, i, i)
              for i in range(1, chapters + 1))
ncx = ('<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>t</text></docTitle>'
       '<navMap>' + nav + '</navMap></ncx>')
container = ('<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
             '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
with zipfile.ZipFile(out + ".epub", "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", container)
    z.writestr("OEBPS/content.opf", opf)
    z.writestr("OEBPS/toc.ncx", ncx)
    z.writestr("OEBPS/s.css", css)
    for i, x in enumerate(files, 1):
        z.writestr("OEBPS/c%d.xhtml" % i, x)
print("wrote", out + ".epub", "| chapters:", chapters, "| paragraphs each:", per_chapter)
