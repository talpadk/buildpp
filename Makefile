
man = man
html = mozilla

.PHONY : all
all: buildpp.1.gz buildpp.html

buildpp.1.gz: buildpp.1
	rm -f buildpp.1.gz
	gzip buildpp.1
  
buildpp.1: manual.yo
	yodl2man -o buildpp.1 manual
  

buildpp.html: manual.yo
	yodl2html -o buildpp.html manual
  

.PHONY : show showhtml 
show: buildpp.1.gz
	$(man) ./buildpp.1.gz

showhtml: buildpp.html
	$(html) buildpp.html

.PHONY: install
install:
	cp buildpp.pl /usr/bin/

.PHONY: test
test:
	./buildpp.pl

.PHONY: webupdate
webupdate: 
	bash doWebUpdate.sh

.PHONY : clean
clean:
	rm -f buildpp.1.gz buildpp.1 buildpp.html 
