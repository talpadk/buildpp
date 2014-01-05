#!/bin/bash
# Script to generate a new file release
# Should only be run on the master branch, with all changes pushed


VERSION=`perl -e '$d=\`git describe\`;  $major="?"; $minor="?"; $commit="?"; if ($d =~ /^V(\d+).(\d+)-(\d+)-/) { $major=$1;$minor=$2;$commit=$3 } elsif  ($d =~ /^V(\d+).(\d+)/){ $major=$1;$minor=$2;$commit=0  } print "v$major.$minor.$commit";'`

rm -rf /tmp/buildpp /tmp/buildpp.tar /tmp/buildpp_$VERSION.tar.gz /tmp/buildpp_$VERSION.zip

git archive --format tar --prefix=buildpp_$VERSION/ --output /tmp/buildpp.tar HEAD

cd /tmp
tar -xf buildpp.tar
cd buildpp_$VERSION

make
cd ..
tar -cvzf buildpp_$VERSION.tar.gz buildpp_$VERSION
zip -r buildpp_$VERSION.zip buildpp_$VERSION