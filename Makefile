all: build shell

build:
	docker build -t amiberry_build .

shell:
	docker run -p 5900:5900 -ti --rm amiberry_build
