all: build shell

build:
	docker build -t amiberry_build .

shell:
	docker run -p 5900:5900 -v "$(CURDIR)/volume:/amiberry" -ti --rm amiberry_build --model A1200 -G
