#!/usr/bin/perl -w

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


use strict;
use Fcntl ':mode';
use Cwd;

my $workingDir = &Cwd::cwd();

#a mapping to find the path of a file
my %fileMapping=();

#a cache of level 1 dependencies
my %deps=();

#a cache of the recursive dependencies (also stored i .d files)
my %depCache=();

#a cache of file times -1 = file dos't exist, -2 = cache entry invalid
my %timeStamps=();

#a hash used to remember files pased for this run, also speeds up parsing
my %recurivePassedFiles=();

my @exeFiles=();
my $incDirs="-I. ";

my $doClean = 0;
my $doBuild = 0;
my $doTest = 0;
my $testArguments = "";

#display lots of information
my $verbose = 0;

#if true displays information that you normaly dont need nor want
my $girlie = 0;

#if true show when we rebuild .d files
my $showDBuild = 0;

#if true always show the command used for compilation (else just on error)
my $showCompilerCommand = 0;

#if true always show the command used for linking (else just on error)
my $showLinkerCommand = 0;

my $includeSuffix = "\\.h|\\.cpp";
my $objectSuffix = "o";
my $codeSuffix = "cpp";
my $headerSuffix = "h";
my $exeSuffix = "";
my $target = "";
my $compiler = "g++";
my $linker = "g++";
my $cflags = "-c ";
my $ldflags = "";

#the dir where buildit generates files (.o .exe and .d files)
my $buildDir = "build/";
my @targets = ();

#colour definitions for different types of output
my $colourVerbose = "\033[33m";
my $colourNormal = "\033[37;40m";
my $colourError = "\033[33;41m";
my $colourAction = "\033[32m";
my $colourExternal = "\033[36m";
my $colourWarning = "\033[33m";
my $colourGirlie = "\033[35m"; 

#if false the colour entrys will not be used.
my $useColours = 0;

#if true you are requested to confirm when cleaning
my $cleanConfirm = 1;

sub readConfigFile
{
    my ($filename) = @_;
    my $contents = "";
    my $config;
    if (open ($config, "$filename")) {
	print "reading $filename\n";
	while (<$config>) {
	    $contents .= $_;
	}
	close ($config);
    }
    else {
	print "Warning: unable to open $filename\n";
    }
    eval $contents;
}

readConfigFile("localbuild.pl");



if (!$exeSuffix eq ""){
    $exeSuffix = ".$exeSuffix";
}

#searcehs a dir for files that may be used to gennerate .o and exe files with
sub findFilesInDir
{
  my $dirName =  $_[0];
  $dirName =~ s/[\n\r]+$//;
  my $dir;
  opendir ($dir, $dirName)
    || die "Can't find directory '$dirName' specified in modulelist";
  
  my @entrys = readdir $dir;
  
  my $usableFiles = 0;
  
  foreach(@entrys){
    if ($_ !~ /^\.+$/){
      #it was not .. or .
      my $fileName = $dirName."/".$_;
      my $mode = (stat($fileName))[2];
      if (S_ISDIR($mode)){
        findFilesInDir($fileName);
      }
      else {
        if ($_ =~ /(^.*)($includeSuffix)$/){
          $usableFiles = 1;
          my $entry = $_;
          if (!exists($fileMapping{$entry})){
            $fileMapping{$entry} = $dirName."/";
            #print "found $entry in $dirName\n";
        }
      
        }
        elsif ($_ =~ /\.auto$/){
          my $name = $_;
          print $colourExternal."Updating $name in $dirName$colourNormal\n";
          chdir($dirName);
          print `./$name`;
          chdir($workingDir);
        }
      }
    }
  }
  closedir $dir;
  if ($usableFiles == 1){
    $incDirs = $incDirs."-I$dirName ";
  }
}

#reads the modulelist file and generates the search tables for building
sub readModuleList
{
  print $colourAction."Reading module list and compiling file list$colourNormal\n";
  open (moduleList, "<modulelist")
    || die "Can't open modulelist";
    
  while (<moduleList>){
    my $dirName = $_;
    findFilesInDir($dirName);
  }

  close moduleList;
}

#reads the commandline arguments
sub parseArguments
{
    foreach(@ARGV){
	if ($_ eq "-clean"){
	    $doClean = 1;
	}
  elsif ($_ eq "-verbose"){
    $verbose = 1;
  }
  elsif ($_ eq "-girlie"){
    $girlie = 1;
  }
elsif ($_ eq "-showdbuild"){
    $showDBuild = 1;
  }  
  elsif ($_ eq "-usecolours" or $_ eq "-usecolors"){
    $useColours = 1;
  }
	elsif ($_ =~ /^-test(.*)/){
	    $testArguments = $1;
	    $doTest = 1;
	}
	else {
	    my $argument = $_;
	    $argument =~ s/^.*\///;
	    #if (exists($fileMapping{$argument.".$codeSuffix"})){
		push(@targets, $argument);
	    #}
	    #else{
		#die "You are trying to build '$_' but I don't know ".
		 #   "anything about that component\n";
	   # }
	}
    }
    if (scalar(@targets) != 0 || ($doClean == 0)){
	$doBuild = 1;
    }
}

#generates a string that can be used to search the filelist for files that
#the user has requested a build of
sub makeMatchString
{
  my $match="";
  if (scalar(@targets) == 0){
    $match = ".*\.$codeSuffix";	
  }
  else {
    foreach (@targets){
      $match = $match.$_.".$codeSuffix|";
    }
    $match =~ s/\|$//;
  }
  return $match;
}

#removes the specified object files
sub removeObjectFiles
{
    print $colourAction."Removing object files$colourNormal\n";
    my $match = makeMatchString();
    foreach(keys(%fileMapping)){
	unlink(($fileMapping{$_}.$_.".".$objectSuffix));
    }
}



#gets the time stamp of the first argument (file (-path + sufix))
sub getTime
{
  my $filename = $_[0];
  my $result = -1;

  if (exists($timeStamps{$filename}) and $timeStamps{$filename} != -2){
    $result = $timeStamps{$filename};
  }
  else {
   my @fileStatus = stat($filename);
    if (scalar(@fileStatus) == 0){
      $result = -1;
    }
    else {
      $result = $fileStatus[9];    
    }
  }
  $timeStamps{$filename} = $result;

  return $result;
}

#parses a file and gennerates a parsed version in memory (only 1. level deps are
#generated, code files will also gennerate linker level 1. information
#first argument is the name of the file without path
sub parseFile
{
  my $filename = $_[0];

  if (exists($deps{$filename})){
    return;
  }

  if ($verbose){
    print $colourVerbose."Parsing file $filename".$colourNormal."\n";
  }

  if (!exists($fileMapping{$filename})){
    die $colourError."Unable to find file '$filename'".$colourNormal."\n";
  }
  my $filePath = $fileMapping{$filename}.$filename;

  #parse it 
  my $file;
  my @includeList=();
  my $currentTarget = "all";

  open ($file, "<$filePath") 
		|| die "Unexpected error unable to read $filePath";

  while (<$file>){
    my $line = $_;  
    if ($line =~ /\/\/\/\#target\s+(\S+)/){
      $currentTarget = $1;
    }
    if ($currentTarget eq "all" or $target eq $currentTarget){
      if ($line =~ /(\#include\s*\"\s*\S+\s*\")/){
        push (@includeList, $1);
      }
      if ($line =~ /\/\/\/(\#\S+\s?\S*)\s*/){
        push (@includeList, ($1));
      }
    } 
  }
  close($file);
  
  $deps{$filename} = \@includeList;
}


#parses a given file recursivly returning a list of alle include and
#link dependencies
#returns a list of all dependencies
#first argument is the name of the file without path
sub parseFileRecurcive
{
  my $file = $_[0];
  my @result=();

  if (exists($recurivePassedFiles{$file})){
    return @result;
  }
  
  $recurivePassedFiles{$file} = "";
  
  parseFile($file);
  
  if (!exists($deps{$file})){
    die $colourError.
      "Trying to get recursive dependencie information for $file, ".
      "it has not been created$colourNormal\n";
  }

  my @dep = @{$deps{$file}};
  my %unique = ();
  @result = @dep;
  for my $item (@dep){
    if ($item =~ /\#link\s+(\S+)/){
      my $newFile = $1;
      parseFile($newFile.".$codeSuffix");
      my @subItem = parseFileRecurcive($newFile.".$codeSuffix");
      for my $subSubItem (@subItem){
        if ($subSubItem =~ /\#link/ || $subSubItem =~ /\#ldflags/){
          if (!exists($unique{$subSubItem})){
            push (@result, $subSubItem);
            $unique{$subSubItem} = " ";
          }
        }
      }
    }
    else{ if ($item =~ /\#include\s+\"\s*(\S+)\s*\"/){
      my $newFile = $1;
      parseFile($newFile);
      my @subItem = parseFileRecurcive($newFile);
      for my $subSubItem (@subItem){
        if (!exists($unique{$subSubItem})){
          push (@result, $subSubItem);
          $unique{$subSubItem} = " ";
        }
      }
    }}
  }
  return @result;
}


#gennerate .d file on disk (cached version of parseFile)
#includes all levels
#first argument is the name of the file without path
sub parseFileCached{
  my $filename = $_[0];
  
  if (exists($depCache{$filename})){
    my @result = @{$depCache{$filename}};
    return @result;
  }
  
  if ($verbose){
    print $colourVerbose."Testing $filename.d$colourNormal\n";
  }
  
  my $dFilename = $buildDir.$filename.".d";
  my $dTime = getTime($dFilename);
  my $fileTime = getTime($fileMapping{$filename}.$filename);
  
  my $rebuild = 0;
  
  if ($dTime == -1 or $dTime <= $fileTime){
    $rebuild = 1;
  }
  else {
    my $dFile;
    open ($dFile, "<$dFilename") ||
      die ($colourError."Unexpected error unable to open $dFilename for input".
           $colourNormal."\n");
    while (<$dFile>){
      my $line = $_;
      if ($line =~ /\#include\s+\"(\S+)\"/){
        my $depName = $1;
        if (!exists($fileMapping{$depName})){
          die ($colourError."Unknown file $depName$colourNormal\n");
        }
        my $depPath = $fileMapping{$depName};
        my $depTime = getTime($depPath.$depName);
        if ($depTime >= $dTime){
          $rebuild = 1;
          last();
        }
      }
      if ($line =~ /\#link\s+(\S+)/){
        my $depName = $1.".$codeSuffix";
        if (!exists($fileMapping{$depName})){
          die ($colourError."Unknown file $depName$colourNormal\n");
        }
        my $depPath = $fileMapping{$depName};
        my $depTime = getTime($depPath.$depName);
        if ($depTime >= $dTime){
          $rebuild = 1;
          last();
        }
      }
    }
  }
  
  my @deps = ();
  
  if ($rebuild){
    if ($showDBuild){
      print $colourAction."Building $filename.d$colourNormal\n";
    }
    
    @deps = parseFileRecurcive($filename);
    
    my $outFile;
    open ($outFile, ">$dFilename") ||
      die $colourError."Unable to write to $dFilename$colourNormal\n";
    
    for my $fileLine (@deps){
      print $outFile $fileLine."\n";
    }
    
    close ($outFile);
    $depCache{$filename} = \@deps;
    #invalidate timestamp of .d file
    $timeStamps{$dFilename} = -2;
  }
  else {
    my $dFile;
    open ($dFile, "<$dFilename") ||
      die ($colourError."Unexpected error unable to open $dFilename for input".
           $colourNormal."\n");
    
    while (<$dFile>){
      push (@deps, $_);
    }
    close($dFile);
  }
  
  return @deps;
}




#builds an object file
#first argument is the code file to use l
sub generateObjectFile
{
  my $filename = $_[0];

  if ($verbose){
    print $colourVerbose."Generating $filename.$objectSuffix$colourNormal\n";
  }

  if (!exists($fileMapping{$filename.".$codeSuffix"})){
    die $colourError."Tryed to compile $filename.$codeSuffix file not found".
      "$colourNormal\n";
  }

  my $codeTime = getTime($fileMapping{$filename.".$codeSuffix"}.
                         $filename.".$codeSuffix");
  my $objTime = getTime($buildDir.$filename.".$objectSuffix");
  
  my $needsRebuild = 0;

  if ($objTime == -1 or $objTime <= $codeTime){
    $needsRebuild = 1;
    if ($girlie){
      print $colourGirlie."You have rearranged $filename.$codeSuffix now I ".
      "need to recompile $filename.$objectSuffix!$colourNormal\n";
    }
  }


  my $path = $fileMapping{$filename.".$codeSuffix"};
 
  %recurivePassedFiles = ();
  my @includeList = parseFileCached($filename.".$codeSuffix");

  for my $incFile (@includeList){
    if ($incFile =~ /\#include\s+\"\s*(\S+)\s*\"/){
      $incFile = $1;
      if (!exists($fileMapping{$incFile})){
        die $colourError."Could not find $incFile$colourNormal\n";
      }
      my $incTime = getTime($fileMapping{$incFile}.$incFile);
      if ($incTime >= $objTime){
        $needsRebuild = 1;
        if ($girlie){
          print $colourGirlie."You keep changing $incFile now I ".
          "need to recompile $filename.$objectSuffix!$colourNormal\n";
        }
        last();
      }
    }
  }


  if ($needsRebuild){
    %recurivePassedFiles = ();
    my @linkList = parseFileCached($filename.".$codeSuffix");
    my $linkLine = "$filename.$objectSuffix";
    my %linkMap = ();
    my $myCFlags = $cflags;
  
    for my $item (@linkList){
      if ($item =~ /^#cflags\s+(.*)\s*/){
        $myCFlags = $myCFlags." $1";
      }
    }

    my $command = "$compiler -o$buildDir$filename.$objectSuffix $myCFlags $incDirs $path$filename.$codeSuffix";
    print $colourAction."Compiling $filename.o$colourNormal\n";
    
    if ($showCompilerCommand == 1){
        print "$command\n";
    }
    `$command`;
    if ($? != 0) {
      print $colourError."Compiling of $filename.$objectSuffix failed$colourNormal\n";
      if (!$showCompilerCommand){
        print "$command\n";
      }
      unlink($filename.".".$objectSuffix);
        die $colourError."   Sorry   $colourNormal\n";
    }
    $timeStamps{$buildDir.$filename.".$objectSuffix"} = -2;
  }
}

#gennerates an exe file from a path without suffix
sub generateExeFile
{
  my $filename = $_[0];

  generateObjectFile($filename);

  my $exeTime = getTime($buildDir.$filename."$exeSuffix");
  my $objTime = getTime($buildDir.$filename.".$objectSuffix");
  
  my $needsRebuild = 0;

  if ($exeTime == -1 or $exeTime <= $objTime){
    $needsRebuild = 1;
    if ($girlie){
      print $colourGirlie.
      "Uhh $filename$exeSuffix is younger than ".
      "$filename.$objectSuffix relinking will be required $colourNormal\n";
    }
  }

  %recurivePassedFiles = ();
  my @linkList = parseFileCached($filename.".$codeSuffix");
  my $isExe = 0;
  my $linkLine = "$buildDir$filename.$objectSuffix";
  my %linkMap = ();
  $linkMap{"$filename.$objectSuffix"} = " ";
  my $myLdFlags = $ldflags;
  #filter list to contain only valid data
  my @filterList;
  for my $item (@linkList){
    if ($item =~ /^#link\s+(\S+)\s*/){
      my $oFile = $1;
      my $objFile = $oFile.".$objectSuffix";
      if (!exists($linkMap{$objFile})){
        $linkMap{$objFile}=" ";
        generateObjectFile($oFile);
        $objTime = getTime($buildDir.$objFile);
        if ($exeTime <= $objTime){
          $needsRebuild = 1;
          if ($girlie){
            print $colourGirlie."Do you like this new object file $objFile?".
            " Well lets relink $filename$exeSuffix$colourNormal\n";
          }
        }        
        $linkLine = $linkLine." $buildDir$objFile"
      }
    }
    if ($item =~ /^#ldflags\s+(.*)\s*/){
      $myLdFlags = $myLdFlags." $1";
    }
    if ($item =~ /^#exe/){
      $isExe = 1;
    }
  }

  if ($needsRebuild and $isExe){
    my $command = "$linker -o$buildDir$filename$exeSuffix $linkLine $myLdFlags";
    
    print $colourAction."Linking $filename$exeSuffix$colourNormal\n";
    
    if ($showLinkerCommand == 1){
      print "$command\n";
    }
    `$command`;
    if ($? != 0) {
      print $colourError."Linking of $filename$exeSuffix failed$colourNormal\n";
      if (!$showLinkerCommand){
        print "$command\n";
      }
      unlink($filename.$exeSuffix);
        die $colourError."   Sorry   $colourNormal\n";
    }
    $timeStamps{$buildDir.$filename."$exeSuffix"} = -2;
  }
}
    

#ensures that the build directory exists
sub buildDirTest
{
  my @fileStatus = stat($buildDir);
  if (scalar(@fileStatus) == 0){
    print $colourAction."Creating build dir$colourNormal\n";
    mkdir($buildDir);
  }
}

#builds the files requested
sub buildFiles
{
  buildDirTest();
  print $colourAction."Building files$colourNormal\n";
  my $match = makeMatchString();
  foreach(keys(%fileMapping)){
    if ($_ =~ /^($match)$/){
      my $theFile = $_;
      $theFile =~ s/\.$codeSuffix$//;
      generateExeFile($theFile);
    }
  }
}

sub testFiles
{
    for my $file (@targets){
      print $colourAction."Testing $file$colourNormal\n";
      print `$buildDir$file $testArguments`;
    } 
}

$ENV{"target"}=$target;

parseArguments();

if (!$useColours){
  $colourVerbose = "";
  $colourNormal = "";
  $colourError = "";
  $colourAction = "";
  $colourExternal = "";
  $colourWarning = "";
  $colourGirlie = "";
}

readModuleList();

if ($doClean == 1){
  my $proceedWithClean = 1;
  print $colourWarning."Cleaning build directry '$buildDir'";
  if ($cleanConfirm){
    print ", are you sure? Yes or no: ";
    my $answer = <STDIN>;
    if (!($answer eq "Yes\n")){
      $proceedWithClean = 0;
      die $colourWarning."Clean aborted$colourNormal\n";
    }
    else {
      print "Proceeding with clean action"
      
    }
    print "$colourNormal\n"
  }
  else {
    print "$colourNormal\n";
  }
  
  my $dir;
  if ($proceedWithClean && !opendir ($dir, $buildDir)) {
    print "Can't find build directory '$buildDir' unable to clean";
  }
  else {
    my @entrys = readdir $dir;
    
    foreach(@entrys){
      if ($_ !~ /^\.+$/){
        #it was not .. or .
        unlink($buildDir."/$_");
      }
    }
    closedir $dir;
  }
}

if ($doBuild == 1){
  buildFiles();
}
if ($doTest){
  testFiles();
}
