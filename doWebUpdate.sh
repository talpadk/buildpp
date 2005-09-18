#!/bin/bash

cd /tmp
rm -rf buildpp
cvs -z3 -d :ext:sftalpa@cvs.sf.net:/cvsroot/buildpp export -D now buildpp
cd buildpp
make buildpp.html
cp buildpp.html www/
rsync -r www/*.html www/*.png www/tutorials sftalpa@shell.sourceforge.net:www/
