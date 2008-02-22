SVGFILES=$(wildcard *.svg)
PNGFILES=$(subst svg,png,${SVGFILES})

all: ${PNGFILES}

clean:
	rm -f ${PNGFILES}


lxray-large.png: %.png: %.svg
	inkscape -b white -e $@ -w 300 $<

%.png: %.svg
	inkscape -e $@ -w 16 -h 16 $<
