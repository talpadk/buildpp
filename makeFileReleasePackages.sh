#!/bin/bash

cd /tmp
rm -rf buildpp buildpp.tar.gz buildpp.zip
cvs -z3 -d :pserver:anonymous@cvs.sf.net:/cvsroot/buildpp export -D now buildpp
cd buildpp
make
cd ..
tar -cvzf buildpp.tar.gz buildpp
zip -r buildpp buildpp