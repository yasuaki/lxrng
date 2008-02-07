SVGFILES=$(wildcard *.svg)
PNGFILES=$(subst svg,png,${SVGFILES})

all: ${PNGFILES}

clean:
	rm -f ${PNGFILES}

%.png: %.svg
	inkscape -e $@ -w 16 -h 16 $<
