SVGFILES=$(wildcard *.svg)
PNGFILES=$(subst loading.png,loading.gif,$(subst svg,png,${SVGFILES}))

all: ${PNGFILES} favicon.ico

clean:
	rm -f ${PNGFILES} favicon.ico

lxray-large.png: %.png: %.svg
	inkscape -b white -e $@ -w 300 $<

loading.gif: loading.svg
	for f in 1 2 3 4 5 6 7 8; do \
	inkscape -b white -e $@-frame$$f.png -C -j -i frame$$f $<; \
	convert $@-frame$$f.png $@-frame$$f.gif; \
	done
	gifsicle --delay=15 --loop $@-frame?.gif > $@
	rm -f $@-frame?.png $@-frame?.gif

%.png: %.svg
	inkscape -e $@ -w 16 -h 16 $<

%.ico: %.png
	icotool -c $< > $@
