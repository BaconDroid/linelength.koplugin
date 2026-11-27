"""Build an EPUB from a novel of the local corpus, so the sample can be exercised on a real book.
Usage: make_epub_corpus.py <corpus.json> <source> <novel> <out.epub>
e.g.   make_epub_corpus.py ~/wm-work/corpus/corpus.json en.novelbuddy delve /tmp/delve.epub"""
import json, sys, zipfile, html

corpus, src, nid, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(corpus))
novel = d[src][nid]
chapters = sorted(novel['chapters'].items(), key=lambda kv: kv[1].get('number', 0))

def xhtml(title, body):
    return ('<?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml">'
            '<head><title>%s</title><link rel="stylesheet" type="text/css" href="s.css"/></head>'
            '<body>%s</body></html>' % (html.escape(title), body))

css = "p { margin: 0; text-indent: 1.2em; text-align: justify; } h2 { text-align: center; margin: 1em 0; }"
files, manifest, spine, nav = [], [], [], []
for i, (key, ch) in enumerate(chapters, 1):
    label = ch.get('label') or ('Chapter %d' % i)
    paras = [p.strip() for p in ch.get('body', '').split('\n') if p.strip()]
    body = ['<h2>%s</h2>' % html.escape(label)]
    body += ['<p>%s</p>' % html.escape(p) for p in paras]
    files.append(('c%d.xhtml' % i, xhtml(label, '\n'.join(body))))
    manifest.append('<item id="c%d" href="c%d.xhtml" media-type="application/xhtml+xml"/>' % (i, i))
    spine.append('<itemref idref="c%d"/>' % i)
    nav.append('<navPoint id="n%d" playOrder="%d"><navLabel><text>%s</text></navLabel><content src="c%d.xhtml"/></navPoint>'
               % (i, i, html.escape(label), i))

opf = ('<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">'
       '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>%s</dc:title><dc:language>en</dc:language>'
       '<dc:identifier id="id">%s</dc:identifier></metadata><manifest>%s'
       '<item id="s" href="s.css" media-type="text/css"/><item id="n" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
       '</manifest><spine toc="n">%s</spine></package>') % (html.escape(novel.get('title', nid)), nid, ''.join(manifest), ''.join(spine))
ncx = ('<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/>'
       '<docTitle><text>%s</text></docTitle><navMap>%s</navMap></ncx>') % (html.escape(nid), ''.join(nav))
container = ('<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
             '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')

with zipfile.ZipFile(out, 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', container)
    z.writestr('OEBPS/content.opf', opf)
    z.writestr('OEBPS/toc.ncx', ncx)
    z.writestr('OEBPS/s.css', css)
    for name, data in files:
        z.writestr('OEBPS/' + name, data)
print("wrote", out, "chapters:", len(files))
