#!/bin/bash
# A script to update the Sourceforge webpage.
# Uses the HEAD of your current branch, remember to commit prior to calling. 

rm -rf /tmp/buildpp /tmp/buildpp.tar
git archive --format tar --prefix=buildpp/ --output /tmp/buildpp.tar HEAD
cd /tmp
tar -xf buildpp.tar
cd buildpp
make buildpp.html
cp buildpp.html www/
rsync --progress -r www/*.html www/*.png www/tutorials sftalpa@web.sourceforge.net:/home/project-web/buildpp/htdocs
