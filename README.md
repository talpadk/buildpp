# Buildpp

## Buildpp because machines should be doing your work
A perlscript to build C++ and C source code into programs, like make in purpose but without makefiles.  
Dynamically finds the dependencies at build time.  
Build in support for cross-platform programs, multi threaded compiling and distcc.

Buildpp used to be hosted on [sourceforge.net](https://sourceforge.net/projects/buildpp/),
but as I a long time ago have stopped using them I have moved the project here.

## Some reasons for using buildpp
* You have a lot of source files and don't want to specify the header file dependencies but still want a proper rebuild of the file if the headers change.  
***Let buildpp scan your source code and recursively determine the dependencies for each file depending on what it #includes.***
* You like to separate functionality into different files, but hate maintaining list of object files that needs to be linked into your project.  
***Use "Lazy Linking", if your code #includes a header buildpp will build the corresponding source file and link it for you.***
* You need an easy way to customize the cflags and linker options from file to file  
***The source knows best... specify compilation options and linker options as comments in the code.***

## Getting / installing buildpp
Getting buildpp is as simple as cloning this repository

buildpp.pl doesn't have any external dependencies (apart form perl), and as such does not require installation.

But if you so desire you can install it by invoking "make install", it simply copies the script to /usr/bin and has even been tested in a cygwin environment.

The recommended way to use buildpp is however to simply copy it into your project folder and commit it along with the rest of the project.
